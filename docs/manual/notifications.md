# Notifications

## Surfaces

| Surface | When | Dismiss |
|---------|------|---------|
| **Island peek** | Critical, warning, replyable (default **One place**) | **Swipe up**, × button, or Open |
| **Toast** (top-right) | Everything else (or **Both** in settings) | **Swipe right/up**, right-click, × |
| **Center** (Super+N) | History, search, Reply | ⌦ dismiss row |

Default **One place** means WhatsApp-style alerts often **only peek from the notch** — they do **not** also appear as a corner toast. Swipe works on **peek**, not only on toasts.

## Privacy (sensitive apps)

Settings → Notifications → **Hide sensitive message text** (default **on**).

For chat/mail apps (WhatsApp/ZapZap, Telegram, Signal, Discord, Gmail, …):

- **Title / app** stay visible (who sent it).
- **Body** is replaced with “Message hidden · Open to read” until you **Open** the notification.
- Critical/warning alerts are never redacted.

## Do Not Disturb (most common “nothing shows”)

- **Focus** (purple chip, Super+Alt+N, center moon): blocks normal toasts; only **critical** breaks through.
- **Screen share**: `mute-on` while sharing (not saved to disk); `rice notifs dnd-off` clears Focus **and** share mute.
- Check: island bell **slash**, hover text **Focus on** / **Held while sharing**.

## Music / media (not in the notification card)

Notifications are for **alerts**, not playback control. Media lives in the **island**:

- **Hover the island** → art, waveform, hover controls; click art to focus the player.
- **Now Playing panel**: hover the playing row or preview from rest activity → **seek bar**, ⏮ ⏯ ⏭, shuffle/repeat when supported.
- **Keys** (with panel focused): Space play/pause, ←/→ ±10 s (Shift ±30 s), N/P next/prev, S shuffle, R repeat.
- **Hardware**: XF86Audio*, Super+F6/F7/F8 for media (F7/F8 are **not** brightness — see binds).

## ZapZap / WhatsApp

- Not from `rice-feeds` (that is GitHub + Gmail only).
- Needs **org.freedesktop.Notifications** owned by **qs** (`rice restart`).
- After a **shell load failure**, restart **ZapZap** (it may disable the backend for the session).
- WhatsApp often **won’t notify** for the chat/window you’re already in.

## rice-feeds

`systemctl --user status rice-feeds` · `rice feeds status` · hints in `NotifAdapters` (`x-rice-feed`).

## Stress test

`bin/rice-fixture notifs worst` · `bin/rice-notify` (D-Bus, when `notify-send` is broken).
