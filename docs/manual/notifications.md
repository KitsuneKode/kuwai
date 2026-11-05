# Notifications

## Surfaces

- **Toast** (top-right): most apps, including ZapZap/WhatsApp when DND is off.
- **Island peek**: critical, warning, replyable (unless Settings → one place only).
- **Center** (Super+N): full history, search, Open/Reply on select.

## Do Not Disturb (most common “nothing shows”)

- **Focus** (purple chip, Super+Ctrl+G, center moon): blocks normal toasts; only **critical** breaks through.
- **Screen share**: `mute-on` while sharing (not saved to disk); `rice notifs dnd-off` clears Focus **and** share mute.
- Check: island bell **slash**, hover text **Focus on** / **Held while sharing**.

## ZapZap / WhatsApp

- Not from `rice-feeds` (that is GitHub + Gmail only).
- Needs **org.freedesktop.Notifications** owned by **qs** (`rice restart`).
- After a **shell load failure**, restart **ZapZap** (it may disable the backend for the session).
- WhatsApp often **won’t notify** for the chat/window you’re already in.

## rice-feeds

`systemctl --user status rice-feeds` · `rice feeds status` · hints in `NotifAdapters` (`x-rice-feed`).

## Stress test

`bin/rice-fixture notifs worst` · `bin/rice-notify` (D-Bus, when `notify-send` is broken).
