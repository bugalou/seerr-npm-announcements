# Seerr Announcements for Nginx Proxy Manager

Display queued, plain-text announcements over Seerr using Nginx Proxy Manager
(NPM). Each announcement can expire automatically and is dismissed separately
in each browser. The supplied Bash script manages the JSON file on the Docker
host. No changes to Seerr's source code or container image are needed.

This is an unofficial HTML-injection customization, not a built-in Seerr
feature. Test it after Seerr or NPM upgrades. No web management service,
credentials, live announcements, or private server settings are included.

## Files

The release layout is:

```text
shared/
  seerr_notice.js
  seerr_announcements.json
  manage_seerr_announcements.sh
  npm-advanced.conf
share/
  README.md
```

- [seerr_notice.js](../shared/seerr_notice.js): fetches announcements and displays them.
- [seerr_announcements.json](../shared/seerr_announcements.json): disabled example data.
- [manage_seerr_announcements.sh](../shared/manage_seerr_announcements.sh): local CLI manager.
- [npm-advanced.conf](../shared/npm-advanced.conf): complete example for a dedicated Seerr proxy host's Advanced tab.

## Requirements

- A working Docker-based NPM installation and a Seerr instance reachable from it.
- A dedicated hostname such as `requests.example.com`, with working DNS and HTTPS.
  Seerr supports subdomains; subfolder hosting is not officially supported.
- NPM's `/data` directory bind-mounted from the Docker host so the supporting
  files can be updated outside the container.
- Nginx's HTTP substitution module (`sub_filter`), available in the NPM image
  used for this setup. Custom images must provide it too.
- For the manager: Linux, Bash, `jq`, `flock` (usually from `util-linux`), GNU
  `date`, GNU `readlink`, and standard coreutils. Linux's UUID source under
  `/proc/sys/kernel/random/uuid` or the `uuidgen` command is also required.

**The NPM configuration below is required. Copying the JavaScript and JSON
alone will not load announcements in Seerr.** NPM must serve both files and
inject the script into uncompressed HTML responses.

See also the [official Seerr reverse proxy documentation](https://docs.seerr.dev/extending-seerr/reverse-proxy).

## 1. Check the NPM Docker Mount

A typical existing Compose service contains:

```yaml
services:
  app:
    # Keep your existing NPM image, environment, ports, and other settings.
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
```

This is a volume excerpt, not a complete Compose file. Do not replace your
existing deployment with it. Relative host paths are resolved by Compose.

With this mapping, host `./data/nginx/custom/` appears in NPM as
`/data/nginx/custom/`. If `/data` is already mounted elsewhere, use that host
directory instead; do not overlay an empty directory on existing NPM data.

Mount the directory, not each supporting file separately. The manager replaces
JSON atomically, and an individual file bind mount can keep serving the old
file after replacement. Changes to Compose mounts require recreating the NPM
container; ordinary JSON or JavaScript edits do not.

## 2. Install the Supporting Files

From the repository root, assuming the existing NPM host data directory is
`./data`:

```bash
mkdir -p ./data/nginx/custom
cp ./shared/seerr_notice.js ./data/nginx/custom/
cp ./shared/seerr_announcements.json ./data/nginx/custom/
cp ./shared/manage_seerr_announcements.sh ./data/nginx/custom/
chmod 755 ./data/nginx/custom/manage_seerr_announcements.sh
chmod 644 ./data/nginx/custom/seerr_notice.js ./data/nginx/custom/seerr_announcements.json
```

Adjust the destination if your Compose project is elsewhere. These commands
are for initial installation: back up existing data before replacing an
announcement JSON file. The supplied example is disabled and displays nothing.

The account running the manager needs write permission to the JSON directory
and lock file, not just the JSON file. NPM's worker needs directory traversal
and file-read permission. Use a dedicated owner or trusted group as appropriate
for your deployment; do not use `chmod 777`. The manager writes files with mode
`0664` and a `0002` umask, so only trusted administrators should have group
write access. Adapt ownership, ACLs, and SELinux labels to your host as needed.

No `.env` file is required. The script finds the JSON beside itself; the
browser fetches a same-origin URL. Your hostname, backend address, backend
port, and TLS certificate stay in NPM. The `.sh` file need not be executable
if you always invoke it with `bash`.

## 3. Configure the NPM Proxy Host

Back up the current host configuration first.

1. Create or edit the dedicated Seerr proxy host in NPM.
2. In **Details**, enter your own hostname, upstream scheme, upstream address,
   and Seerr port (normally `5055`). These are the existing NPM settings, not
   values to hardcode into the supplied snippet.
3. Disable **Cache Assets**. Choose a valid certificate, enable **Force SSL**,
   and enable **HTTP/2 Support** in the SSL settings.
4. In **Advanced**, use the contents of `shared/npm-advanced.conf`. It already
   defines `location /`; replace or merge any existing definition instead of
   appending a duplicate. Do not also configure a `/` Custom Location.
5. Save and confirm that NPM keeps the proxy host online. If you have container
   shell access, run `docker compose exec app nginx -t`, replacing `app` with
   your actual service name.

The example is an NPM **server-context Advanced snippet**, not a standalone
Nginx configuration. NPM supplies `$forward_scheme`, `$server`, and `$port`
from the Details tab and handles the listeners and TLS certificate.

It serves these exact same-origin paths:

| URL | File inside NPM |
| --- | --- |
| `/__seerr_announcement.json` | `/data/nginx/custom/seerr_announcements.json` |
| `/__seerr_notice.js` | `/data/nginx/custom/seerr_notice.js` |

`proxy_set_header Accept-Encoding ""` requests uncompressed upstream HTML so
`sub_filter` can find `</head>` and inject the script tag. Nginx can still gzip
the response sent to the browser. The substitution defaults to `text/html`;
do not add another `sub_filter_types text/html` directive. Missing closing-head
tags, incompatible response content types, or a restrictive Content Security
Policy can prevent injection or execution. Preserve application security
policies rather than disabling CSP wholesale.

The custom location handles forwarded headers and WebSocket upgrades itself;
it does not rely on NPM's generated default location. The example assumes NPM
terminates TLS directly. Additional trusted proxy/CDN layers may require
different scheme, port, and real-client-IP handling.

**Existing security configuration:** review authentication, access lists,
custom locations, rate limits, and security headers before adopting this
snippet. A custom `location /` may bypass directives NPM normally puts in its
generated location. Do not assume access lists protect these new locations.
Validate your specific policy for the proxied app and both static endpoints.

If several Seerr hosts share one NPM instance, apply the snippet to each host
to share the same JSON. Acknowledgments remain separate for each browser
origin, including different hostnames.

## 4. Verify the Installation

Use your own hostname:

```bash
curl -fsS https://requests.example.com/__seerr_announcement.json | jq .
curl -fsSI https://requests.example.com/__seerr_notice.js
```

Both endpoints should return HTTP 200 and `Cache-Control: no-store, max-age=0`.
The JSON should have an `application/json` content type, and the script should
have `application/javascript`. Authentication policies may require an
authenticated browser instead of anonymous `curl` requests.

Create a test announcement with the manager, then reload Seerr. Confirm that
the HTML contains the injected script tag, the browser requests both files,
the message appears, and acknowledgment prevents it from returning after a
reload. Try a private browser window to confirm a fresh browser sees it. Remove
the test announcement when finished.

JSON and script changes take effect on the next full page load without an NPM
restart. Already open pages do not poll for changes; in-app navigation may not
reload the script. Editing the Advanced configuration requires saving it in
NPM. To roll back, restore the previous Advanced text and remove the test data.

## Using the Shell Announcement Manager

Run on the Docker host, not inside the NPM container. Dependencies can be
installed using your Linux distribution's package manager; for example, Debian
and Ubuntu provide `jq`, `util-linux`, and `coreutils` packages.

From the NPM Compose directory:

```bash
bash ./data/nginx/custom/manage_seerr_announcements.sh list
bash ./data/nginx/custom/manage_seerr_announcements.sh add
bash ./data/nginx/custom/manage_seerr_announcements.sh remove
bash ./data/nginx/custom/manage_seerr_announcements.sh remove ANNOUNCEMENT_ID
bash ./data/nginx/custom/manage_seerr_announcements.sh prune
bash ./data/nginx/custom/manage_seerr_announcements.sh clear
```

- `add` prompts for a title, a single-line message, and an optional future UTC
  expiration. It generates a fresh UUID and enables the new announcement.
- `list` displays all entries, including disabled and expired entries.
- `remove` prompts for an ID; `remove ID` skips that prompt.
- `prune` permanently removes expired entries. Expired announcements are
  already hidden by the browser even before pruning.
- `clear` removes every entry only after the exact confirmation `yes`.

There is no CLI edit/disable command. Remove and re-add an announcement, or use
your own editor/writer following the JSON rules below. The manager creates an
empty JSON file if none exists, uses `flock` to serialize cooperating writers,
and replaces the file atomically. It releases locks before interactive prompts.
Back up data before destructive operations.

If the script is stored separately, override the JSON directory for each run:

```bash
SEERR_NOTICE_DIR=/path/to/npm/data/nginx/custom bash ./shared/manage_seerr_announcements.sh list
```

That path is on the Docker host, not the container. The script resolves JSON
symlinks before writing, so it preserves an existing symlink and locks next to
the canonical target file. The target must also be reachable inside NPM's
mounts. No shared browser/server `.env` is needed or served.

## Building Your Own Announcement Manager

Any trusted local tool can write the JSON; the Bash manager is optional. The
browser only reads it and does not use a management API.

- Write UTF-8 JSON, serialize with a JSON library, and validate the whole
  document and entry fields before publishing. The bundled script only checks
  the top-level object/array on load; it is not a full schema validator for
  third-party data.
- Assign unique IDs. Use a new ID whenever users should acknowledge an updated
  message again; retaining an ID retains previous browser acknowledgments.
- Use the strict UTC expiration format documented below. Do not mix offsets,
  fractional seconds, local dates, and blank strings: the CLI pruning code
  compares normalized timestamp strings.
- Resolve symlinks, acquire an exclusive `flock` on `<canonical JSON path>.lock`,
  read the current JSON under the lock, write a temporary file in the same
  directory, preserve readable permissions, and rename it over the target.
  Release the lock afterward. Do not replace the lock file itself.
- Do not truncate or overwrite the live JSON in place while browsers may read
  it. All writers must honor the same lock to prevent lost updates.
- Keep management interfaces and filesystem write access private. Do not
  expose a shell runner or unauthenticated JSON write endpoint through NPM.

## Limitations and Security

Announcements are **not confidential**: the example serves their JSON to anyone
who can reach the endpoint, including before Seerr login. Disabled and expired
entries remain visible in raw JSON until removed. Never store tokens, passwords,
personal information, or internal operational details in this file.

Message and title text is assigned using `textContent`, not interpreted as
HTML. Markdown, HTML links, and arbitrary scripts in messages are not rendered.
Acknowledgments live in `localStorage`, not user accounts: clearing storage,
using another device/browser, or changing hostnames makes notices appear again.
If storage is blocked, a notice can be shown again on later page loads.

This is a dismissible browser overlay, not an authorization mechanism, audit
trail, or guaranteed delivery system. Users can bypass it. Expiration depends
on the browser's clock, is checked on page load and when advancing the queue,
and does not forcibly close a displayed notice at the exact expiration time.

Only the `shared/` files and this README belong in the public package. Do not
publish an NPM database, entire `/data` directory, certificates, private keys,
existing announcement history, `.env` secrets, or management credentials. No
Python web manager is part of this package.

## JSON Format and Example

The file must be a JSON object containing an `announcements` array. Entries are
displayed in array order, one at a time, when enabled, valid, unexpired, and not
already acknowledged in that browser.

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | Nonempty string | Unique acknowledgment key; change it to request acknowledgment again. |
| `enabled` | Boolean | Only literal `true` displays an entry; not the string `"true"`. |
| `title` | String | Dialog title; use a nonempty value. The browser defaults to `Service Announcement` if omitted or empty. |
| `message` | Nonempty string | Plain text; JSON `\n` creates a line break. |
| `expiresAt` | String or `null` | Strict UTC `YYYY-MM-DDTHH:MM:SSZ`, or `null` for no expiration. |

Use all five fields for compatibility with the manager. Use unique IDs and
valid future expirations for new notices. The browser skips invalid expiration
dates. To publish no announcements, use `{"announcements": []}`.

The following entries are disabled intentionally. Replace their text, choose
your own IDs and expiration, and set `enabled` to `true` when ready:

```json
{
  "announcements": [
    {
      "id": "example-maintenance-001",
      "enabled": false,
      "title": "Scheduled Maintenance",
      "message": "The service will be temporarily unavailable.\nPlease try again later.",
      "expiresAt": "2099-01-01T00:00:00Z"
    },
    {
      "id": "example-welcome-001",
      "enabled": false,
      "title": "Service Update",
      "message": "Replace this with a general update for your users.",
      "expiresAt": null
    }
  ]
}
```
