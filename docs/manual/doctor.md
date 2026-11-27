# Doctor and troubleshooting

Run **`kuwai doctor`** (or `./install.sh --doctor`) whenever notifications stop appearing, after a Hyprland upgrade, or before running `kuwai promote`.

## What `kuwai doctor` checks

| Section | Checks |
| --- | --- |
| **Hyprland & kuwai** | Validates `~/.config/kuwai/hypr/hyprland.lua` with `Hyprland --verify-config`, checks live session, units, binds, `shell-auth/` audit, and `pam_faillock` |
| **Notifications** | Checks who owns `org.freedesktop.Notifications` (`qs` vs `dunst` vs empty), `notify-send` status, sends a `bin/kuwai-notify` D-Bus smoke test, and checks saved Focus/DND state |
| **Shell** | Runs `bin/kuwai-check` (load log, orphaned helpers, idle inhibitor guard, memory, CPU, compile check) and queries `limits` state |
| **Services** | Checks `kuwai-feeds.service` and `kuwai-clipboard.service` status, plus ZapZap notification ownership if installed |
| **Channel** | Reports whether the session runs `stable` or `dev` |

Exit code `0` means all checks passed; `1` prints one or more `→` fix lines.

## Common fixes

- **Shell not running or stuck:** run `kuwai restart` (never `killall qs` or bare `qs`). Check status and logs with `kuwai status` and `kuwai logs`.
- **Multiple surfaces misbehaving (password prompt, clipboard, island, idle):** run `kuwai rescue`.
- **Notifications not showing:**
  1. Run `kuwai doctor` to confirm `org.freedesktop.Notifications` is owned by `qs`.
  2. Clear Focus/DND and any stuck screen-share mute: `kuwai notifs dnd-off`.
  3. After a shell outage, restart chat apps (such as ZapZap) that disable their notification backend when the D-Bus owner disappears.
  4. Test D-Bus delivery directly: `bin/kuwai-notify -a test "Title" "Body"`.
- **QML load error after editing in dev:** Quickshell keeps the previous shell running on a broken save; check the log with `qs log -p shell | grep -nE "Failed to load|Configuration Loaded" | tail -2`.
- **Bad update on stable:** run `kuwai rollback` to revert `~/.local/share/kuwai` to `stable-prev` and undo its migrations.

Related: [notifications.md](notifications.md) · [install.md](install.md) · [security.md](security.md).
