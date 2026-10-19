#!/usr/bin/env bash

# Seerr Announcement Manager
# Requires: bash, jq, flock, GNU date, GNU readlink, and coreutils.

set -euo pipefail
umask 002

DIR="${SEERR_NOTICE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"

for cmd in jq flock date readlink; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Missing dependency: $cmd" >&2
        exit 1
    fi
done

mkdir -p "$DIR"
DB=$(readlink -f "${DIR}/seerr_announcements.json")
LOCK="${DB}.lock"

exec 9>"$LOCK"

lock_database() {
    flock -x 9
}

unlock_database() {
    flock -u 9
}

lock_database

if [[ ! -f "$DB" ]]; then
    printf '{"announcements":[]}\n' > "$DB"
    chmod 664 "$DB"
fi

if ! jq -e '
    type == "object" and
    (.announcements | type == "array")
' "$DB" >/dev/null; then
    echo "ERROR: Announcement JSON is invalid." >&2
    exit 1
fi
unlock_database

save_json() {
    local tmp
    tmp=$(mktemp "${DB}.tmp.XXXXXX")

    if ! jq "$@" "$DB" > "$tmp"; then
        rm -f "$tmp"
        echo "ERROR: Failed to update JSON." >&2
        exit 1
    fi

    chmod 664 "$tmp"
    mv -f "$tmp" "$DB"
}

list_announcements() {
    lock_database
    echo
    echo "========================================"
    echo " Seerr Announcements"
    echo "========================================"

    jq -r '
        if (.announcements | length) == 0 then
            "No announcements configured."
        else
            .announcements[] |
            "----------------------------------------",
            "ID:      \(.id)",
            "Title:   \(.title)",
            "Enabled: \(.enabled)",
            "Expires: \(.expiresAt // "Never")",
            "Message: \(.message)"
        end
    ' "$DB"

    unlock_database
    echo
}

add_announcement() {
    local title message expiry id

    echo
    echo "Create New Announcement"
    echo "----------------------------------------"

    read -r -p "Title: " title
    read -r -p "Message: " message

    if [[ -z "${title//[[:space:]]/}" ||
          -z "${message//[[:space:]]/}" ]]; then
        echo "ERROR: Title and message are required."
        exit 1
    fi

    echo
    echo "Expiration format: YYYY-MM-DDTHH:MM:SSZ"
    echo "Leave blank for no expiration."
    echo

    read -r -p "Expiration (UTC): " expiry

    if [[ -n "$expiry" ]]; then
        if [[ ! "$expiry" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] ||
           ! date -u -d "$expiry" >/dev/null 2>&1; then
            echo "ERROR: Invalid UTC expiration date."
            exit 1
        fi

        if (( $(date -u -d "$expiry" +%s) <= $(date -u +%s) )); then
            echo "ERROR: Expiration must be in the future."
            exit 1
        fi
    fi

    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        id=$(cat /proc/sys/kernel/random/uuid)
    elif command -v uuidgen >/dev/null 2>&1; then
        id=$(uuidgen)
    else
        echo "ERROR: UUID generator unavailable." >&2
        exit 1
    fi

    lock_database
    save_json \
        --arg id "$id" \
        --arg title "$title" \
        --arg message "$message" \
        --arg expiry "$expiry" \
        '
        .announcements += [{
            id: $id,
            enabled: true,
            title: $title,
            message: $message,
            expiresAt: (
                if $expiry == "" then null else $expiry end
            )
        }]
        '
    unlock_database

    echo
    echo "Announcement created."
    echo "ID: $id"
}

remove_announcement() {
    local id count

    id="${1:-}"

    if [[ -z "$id" ]]; then
        list_announcements
        read -r -p "Announcement ID to remove: " id
    fi

    lock_database
    count=$(jq --arg id "$id" '
        [.announcements[] | select(.id == $id)] | length
    ' "$DB")

    if [[ "$count" -eq 0 ]]; then
        unlock_database
        echo "Announcement not found: $id"
        return 1
    fi

    save_json --arg id "$id" '
        .announcements |= map(select(.id != $id))
    '
    unlock_database

    echo "Removed announcement: $id"
}

clear_announcements() {
    local confirm

    read -r -p "Remove ALL announcements? (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        echo "Cancelled."
        return
    fi

    lock_database
    save_json '.announcements = []'
    unlock_database

    echo "All announcements removed."
}

prune_announcements() {
    local now before after

    lock_database
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    before=$(jq '.announcements | length' "$DB")

    save_json --arg now "$now" '
        .announcements |= map(
            select(
                .expiresAt == null or
                .expiresAt > $now
            )
        )
    '

    after=$(jq '.announcements | length' "$DB")
    unlock_database

    echo "Removed $((before - after)) expired announcements."
}

case "${1:-}" in
    add)
        add_announcement
        ;;
    list)
        list_announcements
        ;;
    remove)
        remove_announcement "${2:-}"
        ;;
    clear)
        clear_announcements
        ;;
    prune)
        prune_announcements
        ;;
    *)
        echo "Seerr Announcement Manager"
        echo
        echo "Usage: $0 COMMAND"
        echo
        echo "Commands:"
        echo "  add          Add an announcement"
        echo "  list         List announcements"
        echo "  remove [ID]  Remove an announcement"
        echo "  clear        Remove all announcements"
        echo "  prune        Remove expired announcements"
        exit 1
        ;;
esac