# The fresh-install test

kuwai is checked on the owner's machine, where everything is already there. This
test installs it on a machine where nothing is: a clean Arch Linux, a new user,
`./install.sh --deps --yes`, a first login, the lock and its unlock with a real
password, a shell restart, a suspend, the login screen's config, an uninstall. Nothing of the machine it runs on is read or written: no
home, no `~/.config`, no `~/.local/share/kuwai`, no session.

Two ways to run it, the same checks (`inside.sh`):

| | `tests/fresh/run.sh` | `tests/fresh/vm.sh` |
|---|---|---|
| what it is | a docker container with systemd as its init | a qemu/KVM virtual machine, own kernel |
| time | about 10 minutes (3 once the package cache is warm) | about 25 (the base disk is built once, then ~15) |
| install, defaults, consent, uninstall | yes | yes |
| nothing written outside the expected places; what an uninstall leaves | yes | yes |
| shell and login face load (offscreen) | yes | yes |
| PAM: a wrong password refused, the right one accepted, through Quickshell's `PamContext` on `login` | yes | yes |
| `greeter/install --yes`, `--code`, `--undo` (greetd's files written, then put back) | yes | yes |
| `kuwai auth pin` / `unpin` (root's copy of the password prompt) | yes | yes |
| Hyprland, island, lock, panels, `kuwai doctor` | **no** (see below) | yes |
| greetd starts the login screen, which logs the user in and hands off to their session | **no** | yes |
| the lock opened by typing the password, a wrong one first | **no** | yes |
| real logind/PAM session on tty1 | no | yes |
| suspend and resume while locked | no | `--suspend` |
| needs | docker | docker (builds the disk), qemu, KVM |

Why the container cannot start Hyprland: Hyprland 0.57's Aquamarine wants a seat
and a KMS device (`CBackend::create() failed`, "DRM backend failed", "no allocator
available"), and a container has neither. A nested start inside another
compositor fails too: sway, weston and labwc (wlroots 0.20) offer
`xdg_wm_base` v5 and Aquamarine 0.16 binds v6. So the container run covers
everything up to the session and the uninstall, and says SKIP for the rest.

## Run it

```sh
tests/fresh/run.sh                 # the container: install → defaults → uninstall
tests/fresh/run.sh --committed     # test the committed HEAD instead of the working tree
tests/fresh/run.sh --keep          # leave the container up: docker exec -it NAME bash
tests/fresh/run.sh --only install  # skip the session phase even where it could run
tests/fresh/run.sh --gpu           # give the container the render node (never needed)

tests/fresh/vm.sh                  # the VM, everything including the session
tests/fresh/vm.sh --suspend        # and a suspend/resume while locked
tests/fresh/vm.sh --interactive    # keep the VM up in a window afterwards
tests/fresh/vm.sh --rebuild        # build the base disk again (newest Arch)
```

Both print a PASS / FAIL / SKIP / INFO line per check as it happens and finish
with `== summary`. Exit 0 when nothing failed, 1 when a check failed, 2 when it
couldn't start. Logs, the shell's log, doctor output and screenshots go to
`/tmp/kuwai-fresh-TIMESTAMP` (`--out DIR` to choose). It tests the working
tree, uncommitted edits included, by committing a copy inside the guest;
`--committed` (container) tests only HEAD.

What it needs from you: docker with your user in the `docker` group (no sudo,
no privileged container: systemd runs with `--security-opt writable-cgroups`);
for the VM also `qemu-system-x86_64`, `qemu-img`, `mke2fs`, `debugfs`, access to
`/dev/kvm`. The first run downloads about 1 GB of packages into the docker
volume `kuwai-fresh-pkgcache`; this machine's `/var/cache/pacman/pkg` is mounted
read-only as a second package source when it exists (`--no-hostcache` to skip),
which turns a slow line into minutes. `docker volume rm kuwai-fresh-pkgcache`
forgets the cache. The VM's base disk lives in `~/.cache/kuwai-fresh-vm`
(about 2 GB used; delete the folder to forget it).

## What it checks

Machine and install (both):

- `./install.sh --dry-run` exits 0 and changes nothing; `--deps --yes` exits 0
  as a new user with sudo; Hyprland and quickshell arrive; the 0.57 gate passes;
  every package in `packages/core.txt` is there.
- The stable channel is checked out; migrations are recorded and none pending;
  kuwai's Hyprland entry is in `~/.config/kuwai/hypr` and `~/.config/hypr` is
  untouched; the `kuwai` command is linked; the user units are linked.
- A second install exits 0 and changes nothing.
- `system/session` puts "Kuwai" on the login screen and its `Exec` exists.

First-run state (both): `collect.conf` says `clipboard=off` and `feeds=off`; the
clipboard and feeds units are not enabled and nothing of them runs; no cliphist
database; `kuwai-look init` works and the theme is Kuwai Night; the default
wallpaper is a downloaded, checksummed image with its credits beside it; the shell
and the login face load offscreen (`kuwai-loadtest`).

Unlock and the login screen (both):

- `chpasswd` gives the test user a password; a QML fixture
  (`tests/fresh/pamcheck/shell.qml`) starts Quickshell's `PamContext` on
  `config: "login"`, the same stack `shell/modules/lock/Lock.qml` uses, and
  prints the result: a wrong password and an empty one fail, the right one
  succeeds.
- `greeter/install --yes` runs for real inside the guest (its root is the
  guest's): `/etc/greetd/config.toml` starts `/var/lib/kuwai-greeter/compositor-start`
  as `greeter` on vt 1, `/etc/pam.d/greetd` includes `system-login`, the code is
  root's with no links and is the committed revision, the greeter account can
  read the user's name, greetd is enabled. `--code` runs again, then `--undo`
  puts `/etc/pam.d/greetd`, `/etc/greetd/config.toml` and the display-manager
  link back as they were (compared by hash).
- `kuwai auth pin` leaves a root-owned, non-writable copy of the password prompt
  in `/usr/local/share/kuwai/shell-auth`; `unpin` removes it, and exits 0 again
  when run a second time after the uninstall.

Nothing written outside the expected places (both): every file newer than the
start of the install, not owned by a package and not under the home, `/tmp`,
pacman's folders or `/var/log`, is listed in `outside-expected.txt`. The run fails
if one is in a system area (`/etc/pam.d`, `/etc/sudoers.d`, `/opt`, `/root`,
`/usr/local`, another home) or has `kuwai` in its name, unless it is the login
entry from `system/session` (`/usr/local/bin/kuwai-session`,
`/usr/share/wayland-sessions/kuwai.desktop`).

Session (VM only):

- The login entry's command starts Hyprland as a systemd service with a PAM
  session on tty1 (what a greeter does); a monitor exists; `hyprctl
  configerrors` is empty.
- The shell loads (`Configuration Loaded`, no `Failed to load`, no `ERROR`
  lines) and `kuwai-shell.service` is the process running it.
- Over `qs ipc`: `island state` answers; every panel (`test preview`) opens and
  closes; a screenshot (`grim`) isn't one flat colour.
- `lock lock`, then `lock state` becomes `locked` (the compositor confirmed it);
  `kuwai-shell.service` restarts and the session is still locked; with `--suspend`
  the guest suspends while locked, is woken over QMP, and is still locked with
  the same shell process.
- Consent in a live session: copying text with clipboard history off stores
  nothing and starts no `wl-paste`; `kuwai collect clipboard on` starts the
  watchers, `off` stops them; the feeds helper never ran.
- `kuwai doctor` passes; `kuwai-check` (CPU, memory, orphans) is reported but its
  budgets are for a GPU, so under software rendering a miss is INFO, not FAIL.
- Unlock: `wtype` types a wrong password into the lock (it stays locked and
  `faillock` counts one try), then the right one (`lock state` becomes
  `unlocked`); the lock goes up again and opens again. This is the only place a
  keyboard is simulated, and it is the guest's own session.
- Logging out ends the session and nothing of kuwai's keeps running.

The login handoff (VM only, after `greeter/install` and before its `--undo`):
`greetd.service` starts the staged login screen on tty1 and its log has no load
failure. Then it is stopped, `tests/fresh/greeter-input.qml.inc` is added to the
root's copy of `greeter.qml` in the guest, and greetd starts again. That
include reads the test user's password from a file in `/run/kuwai-fresh-greeter`
(a 0700 folder of the `greeter` account) and calls the greeter's own `submit()`,
so the password goes through greetd's PAM stack and nobody types or moves
anything. The test asserts a logind session of the user on seat0 whose service
is `greetd`, the user's Hyprland running, `kuwai-shell.service` active and the
shell loaded, and the greeter's compositor and login face gone; it then logs out,
stops greetd and puts the original `greeter.qml` back.

Uninstall (both): `./install.sh --uninstall` exits 0 (if it says to run it again,
that run is checked too); the login entry is removed and `kuwai auth unpin` run;
every file install placed is gone (the stable checkout and `~/.config/kuwai`,
`~/.local/state/kuwai` stay, as install.sh says, and are not counted); every file
that was there before is as it was; `/usr/local`, the sessions folder, the units
folder and PAM are as before; no directory is left behind outside the home.
`remains.txt` lists what is left: kuwai's own folders in the home, the greeter's
code in `/var/lib/kuwai-greeter` that `greeter/install --undo` keeps, and the
packages `--deps` added (install.sh never removes packages).

## Without docker

`python -m pytest tests/fresh` checks the scripts themselves and needs neither
docker nor qemu: shellcheck-clean (skipped when shellcheck isn't installed);
cleanup traps on exit, INT and TERM; the host-side scripts write only to their
own folders and never run `sudo`, `systemctl`, `pacman` or `useradd` on the host;
docker is only asked to remove the container the script named; no `--privileged`,
no host network, no mount but the package cache; `inside.sh` refuses to run
before it changes anything unless it is root in a container or a marked
throwaway. A stub `docker` runs `run.sh` end to end: the guest's verdict becomes
the exit status, the container is removed on success, failure and SIGTERM, the
staging folder is gone, and the host's home and temp folder are untouched.

## What it can't check

- A GPU. The VM renders in software (llvmpipe on a virtio KMS device): frame
  pacing, the `kuwai-check` CPU/memory budgets, shaders' cost and anything
  GPU-specific (the NVIDIA path, `kuwai gpu`) are not exercised. Run
  `bin/kuwai-check` and `bin/kuwai-rehearse --gate` on real hardware.
- The greeter taking input from a keyboard. greetd, the greeter's compositor and
  its PAM stack run for real in the VM, but the password reaches the login face
  from a file read by the test's include, not from keys; the container never
  starts greetd. Fingerprint (`pam_fprintd`) is not exercised either.
- Real hardware sleep: the VM's suspend is s2idle on QEMU's firmware; lid
  switches, alarms that wake the laptop (`system/install`), NVIDIA resume.
- Network features beyond the one wallpaper download: GitHub/Gmail feeds (no
  accounts), weather, updates over `kuwai promote`.
- A multi-monitor or hot-plug setup: the VM has one virtual output.

## Known limit: `--suspend`

The suspend and resume checks pass (the kernel suspends, the shell keeps its pid,
the lock still holds, the password still unlocks). But in four runs on one
machine the guest then reset itself within a minute or two of resuming, and
`-no-reboot` turns that into qemu exiting with status 0, so the checks after the
suspend (logout, greeter, uninstall) did not finish. Run `--suspend` for the
suspend result and a plain `vm.sh` for the rest; the plain run has never reset.
`out/qemu.log` is empty in those runs; the cause is not known.

## When it fails

Start with `run.log` (or `serial.log` for the VM), then the file named in the
FAIL line (`shell.qslog.txt`, `doctor.log`, `uninstall.log`). `--keep` leaves the
container to look around in; `vm.sh --interactive` leaves the VM up.
