# Doctor

Run **`bin/kuwai doctor`** (or `./install.sh --doctor` after install) when notifications feel dead, before **`kuwai promote`**, or after a shell crash.

## What it checks

| Section | Checks |
|---------|--------|
| **Kuwai** | Hyprland config, live session, units, binds, polkit, faillock |
| **Notifications** | Who owns `org.freedesktop.Notifications` (kuwai vs dunst), broken `notify-send`, **`kuwai-notify` smoke test**, saved Focus/DND |
| **Shell** | **`kuwai-check`**: load log, orphan helpers, idle guard, memory, CPU, compile |
| **Services** | `kuwai-feeds`, clipboard; ZapZap + kuwai owner hint |
| **Channel** | stable vs dev |

Exit **0** = all good, **1** = at least one fix line printed (`→ …`).

## Common fixes

- **No notification owner** → `kuwai restart`
- **DND on** → `kuwai notifs dnd-off` or turn off Focus in the island
- **ZapZap + wrong owner** → `kuwai restart`, then restart ZapZap
- **Shell won't load** → read `kuwai-check` / `kuwai logs`; fix QML, then restart
- **libnotify broken** → ignore for kuwai; kuwai/shell use **`bin/kuwai-notify`**

Related: [notifications.md](notifications.md) · [security.md](security.md).
