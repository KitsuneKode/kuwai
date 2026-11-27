# Notifications

## Surfaces

| Surface | When | Dismiss |
| --- | --- | --- |
| **Island peek** | Critical, warning, or replyable alerts (default **One place**) | **Swipe up**, `×`, or Open |
| **Toast** (top-right) | Normal/low alerts (or **Both** in settings) | **Swipe right/up**, right-click, or `×` |
| **Notification Centre** (`Super+N`) | Grouped history, search, inline Reply | `Delete` dismisses a row (`Ctrl+Z` undoes) |

In the default **One place** mode, chat alerts that can be replied to peek from the notch rather than also showing a corner toast.

## Privacy (sensitive apps and screen sharing)

**`Settings → Notifications → Hide sensitive message text`** is on by default:

- For chat apps (WhatsApp/ZapZap, Telegram, Signal, Discord, Slack, Element, Messenger, Beeper), the app name and sender stay visible while the message body is hidden on toasts, notch peeks, and the lock screen.
- Selecting the row inside the Notification Centre or tapping the peek reveals the body.
- **While sharing your screen**, all non-critical bodies stay hidden everywhere, and normal alerts are muted until screen sharing ends.
- Critical and warning alerts are never redacted.

## Do Not Disturb and Focus

- Toggle Do Not Disturb with **`Super+Alt+N`**, `kuwai notifs dnd`, the moon control in Controls, or right-clicking/holding the island bell.
- `kuwai notifs dnd-off` clears both Focus/DND and any stuck screen-share mute.
- Only **critical** notifications break through Do Not Disturb.

## GitHub and Gmail feeds (`kuwai-feeds`)

`kuwai-feeds` (`systemd/kuwai-feeds.service`) is **off by default**. Enable it during install (`--feeds`) or later with `kuwai collect feeds on`.

- **GitHub:** polls notifications through your existing `gh` CLI login using `If-Modified-Since` (unchanged polls do not consume rate-limit quota). Review requests, mentions, assignments, and failed CI peek from the notch; comments toast; bots stay quiet in the centre unless a check fails.
- **Gmail:** connects over IMAP IDLE (push, no polling) for unread, important Primary mail. Run `kuwai feeds gmail-setup` to store your Gmail address and app password in the system keyring (`secret-tool`). Remove it with `kuwai feeds gmail-forget`.
- Settings live in `~/.config/kuwai/feeds.json` (read on each cycle without restarting):

```json
{
  "gmail": "user@example.com",
  "gmailQuery": "is:unread is:important category:primary",
  "github": {
    "enabled": true,
    "mute": ["someorg/*"],
    "quiet": ["owner/repo"],
    "bots": "quiet"
  }
}
```

Check feed health with `kuwai feeds status` and follow logs with `kuwai feeds logs`.

## Troubleshooting

- Run `kuwai doctor` to verify `org.freedesktop.Notifications` is owned by `qs` (not `dunst` or empty) and that DND is off.
- If a chat app such as ZapZap stops notifying after a shell crash or outage, run `kuwai restart` and then restart the app.
- Send a test notification directly over D-Bus without libnotify: `bin/kuwai-notify -a test "Title" "Body"`, or stress-test with `bin/kuwai-fixture notifs one`.
