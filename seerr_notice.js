/*
 * Seerr Announcement System
 * Multiple announcements, automatic expiration,
 * and per-browser acknowledgment tracking.
 */

(() => {
    "use strict";

    const CONFIG_URL = "/__seerr_announcement.json";
    const STORAGE_PREFIX = "seerr_announcement_ack_";

    async function initialize() {
        let data;

        try {
            const response = await fetch(CONFIG_URL, {
                cache: "no-store",
                credentials: "same-origin"
            });

            if (!response.ok) {
                console.warn("Announcements: HTTP " + response.status);
                return;
            }

            data = await response.json();
        } catch (error) {
            console.warn("Announcements: Could not load JSON", error);
            return;
        }

        if (!data || !Array.isArray(data.announcements)) {
            return;
        }

        const now = Date.now();

        // Select enabled, non-expired, unread announcements.
        const pending = data.announcements.filter(notice => {
            if (!notice || notice.enabled !== true) return false;
            if (typeof notice.id !== "string" || !notice.id) return false;
            if (typeof notice.message !== "string" ||
                !notice.message.trim()) return false;

            if (notice.expiresAt) {
                const expiration = Date.parse(notice.expiresAt);

                if (!Number.isFinite(expiration) ||
                    now >= expiration) return false;
            }

            try {
                const key = STORAGE_PREFIX + notice.id;
                if (localStorage.getItem(key) === "1") return false;
            } catch {}

            return true;
        });

        // Nothing pending: leave Seerr completely alone.
        if (pending.length === 0) return;

        showAnnouncementQueue(pending);
    }

    function showAnnouncementQueue(pending) {
        let index = 0;

        const overlay = document.createElement("div");
        overlay.id = "seerr-notice-overlay";
        overlay.setAttribute("role", "dialog");
        overlay.setAttribute("aria-modal", "true");
        overlay.setAttribute("aria-labelledby", "seerr-notice-title");

        overlay.style.cssText = `
            position:fixed;
            inset:0;
            z-index:2147483647;
            background:rgba(0,0,0,0.82);
            display:flex;
            align-items:center;
            justify-content:center;
            padding:20px;
            box-sizing:border-box;
        `;

        const panel = document.createElement("div");
        panel.style.cssText = `
            background:#20212b;
            color:#f9fafb;
            padding:30px;
            border-radius:12px;
            max-width:540px;
            width:100%;
            box-sizing:border-box;
            font-family:system-ui,sans-serif;
            box-shadow:0 15px 50px rgba(0,0,0,.5);
        `;

        const counter = document.createElement("div");
        counter.style.cssText = `
            color:#a5b4fc;
            font-size:13px;
            margin-bottom:12px;
        `;

        const title = document.createElement("h2");
        title.id = "seerr-notice-title";
        title.style.cssText = `
            font-size:23px;
            margin:0 0 18px;
            color:#ffffff;
        `;

        const message = document.createElement("div");
        message.style.cssText = `
            font-size:16px;
            line-height:1.65;
            color:#d1d5db;
            white-space:pre-wrap;
            overflow-wrap:anywhere;
            margin-bottom:26px;
            max-height:55vh;
            overflow-y:auto;
        `;

        const button = document.createElement("button");
        button.style.cssText = `
            display:block;
            margin-left:auto;
            padding:12px 24px;
            border:0;
            border-radius:7px;
            background:#6366f1;
            color:#ffffff;
            font-size:15px;
            font-weight:600;
            cursor:pointer;
        `;

        const originalOverflow = document.body.style.overflow;

        function closeOverlay() {
            overlay.remove();
            document.body.style.overflow = originalOverflow;
        }

        function renderCurrent() {
            // Skip notices that expired while the modal was open.
            while (index < pending.length) {
                const notice = pending[index];

                if (!notice.expiresAt ||
                    Date.now() < Date.parse(notice.expiresAt)) {
                    break;
                }
                index++;
            }

            if (index >= pending.length) {
                closeOverlay();
                return;
            }

            const notice = pending[index];

            title.textContent = notice.title ||
                "Service Announcement";
            message.textContent = notice.message;

            counter.textContent = pending.length > 1
                ? `Announcement ${index + 1} of ${pending.length}`
                : "Service Announcement";

            button.textContent =
                index < pending.length - 1
                    ? "Acknowledge & Next"
                    : "Acknowledge";

            button.focus();
        }

        button.addEventListener("click", () => {
            const notice = pending[index];

            try {
                localStorage.setItem(
                    STORAGE_PREFIX + notice.id,
                    "1"
                );
            } catch (error) {
                console.warn(
                    "Announcements: Could not save acknowledgment",
                    error
                );
            }

            index++;
            renderCurrent();
        });

        // Keep keyboard focus inside the modal.
        overlay.addEventListener("keydown", event => {
            if (event.key === "Tab") {
                event.preventDefault();
                button.focus();
            }
        });

        panel.append(counter, title, message, button);
        overlay.appendChild(panel);

        document.body.style.overflow = "hidden";
        document.body.appendChild(overlay);

        renderCurrent();
    }

    if (document.readyState === "loading") {
        document.addEventListener(
            "DOMContentLoaded",
            initialize,
            { once: true }
        );
    } else {
        initialize();
    }
})();