# Doctor

Run **`bin/rice doctor`** (or `./install.sh --doctor` after install) when notifications feel dead, before **`rice promote`**, or after a shell crash.

## What it checks

| Section | Checks |
|---------|--------|
| **Kuwai** | Hyprland config, live session, units, binds, polkit, faillock |
| **Notifications** | Who owns `org.freedesktop.Notifications` (rice vs dunst), broken `notify-send`, **`rice-notify` smoke test**, saved Focus/DND |
| **Shell** | **`rice-check`**: load log, orphan helpers, idle guard, memory, CPU, compile |
| **Services** | `rice-feeds`, clipboard; ZapZap + rice owner hint |
| **Channel** | stable vs dev |

Exit **0** = all good, **1** = at least one fix line printed (`→ …`).

## Common fixes

- **No notification owner** → `rice restart`
- **DND on** → `rice notifs dnd-off` or turn off Focus in the island
- **ZapZap + wrong owner** → `rice restart`, then restart ZapZap
- **Shell won't load** → read `rice-check` / `rice logs`; fix QML, then restart
- **libnotify broken** → ignore for rice; kuwai/shell use **`bin/rice-notify`**

Related: [notifications.md](notifications.md) · [security.md](security.md).
