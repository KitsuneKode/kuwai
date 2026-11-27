# The fresh-install test

kuwai is checked on the owner's machine, where everything is already there. This
test installs it on a machine where nothing is: a clean Arch Linux, a new user,
`./install.sh --deps --yes`, a first login, the lock, a shell restart, a
suspend, an uninstall. Nothing of the machine it runs on is read or written: no
home, no `~/.config`, no `~/.local/share/kuwai`, no session.

Two ways to run it, the same checks (`inside.sh`):

| | `tests/fresh/run.sh` | `tests/fresh/vm.sh` |
|---|---|---|
| what it is | a docker container with systemd as its init | a qemu/KVM virtual machine, own kernel |
| time | about 10 minutes (3 once the package cache is warm) | about 25 (the base disk is built once, then ~15) |
| install, defaults, consent, uninstall | yes | yes |
| shell and login face load (offscreen) | yes | yes |
| Hyprland, island, lock, panels, `kuwai doctor` | **no** (see below) | yes |
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
- Logging out ends the session and nothing of kuwai's keeps running.

Uninstall (both): `./install.sh --uninstall` exits 0 (if it says to run it again,
that run is checked too); the login entry is removed; every file install placed
is gone (the stable checkout and `~/.config/kuwai`, `~/.local/state/kuwai` stay,
as install.sh says, and are not counted); every file that was there before is as
it was; `/usr/local`, the sessions folder, the units folder and PAM are as before.

## What it can't check

- A GPU. The VM renders in software (llvmpipe on a virtio KMS device): frame
  pacing, the `kuwai-check` CPU/memory budgets, shaders' cost and anything
  GPU-specific (the NVIDIA path, `kuwai gpu`) are not exercised. Run
  `bin/kuwai-check` and `bin/kuwai-rehearse --gate` on real hardware.
- The greeter. `greeter/install` (greetd) isn't run: a login screen needs a
  display manager taking over a VT. The login face's QML is loaded (offscreen);
  the real PAM unlock and fingerprint paths are not.
- Unlocking. The lock is driven to "locked" and kept locked; typing a password
  into it is the one thing this test never does.
- Real hardware sleep: the VM's suspend is s2idle on QEMU's firmware; lid
  switches, alarms that wake the laptop (`system/install`), NVIDIA resume.
- Network features beyond the one wallpaper download: GitHub/Gmail feeds (no
  accounts), weather, updates over `kuwai promote`.
- A multi-monitor or hot-plug setup: the VM has one virtual output.

## When it fails

Start with `run.log` (or `serial.log` for the VM), then the file named in the
FAIL line (`shell.qslog.txt`, `doctor.log`, `uninstall.log`). `--keep` leaves the
container to look around in; `vm.sh --interactive` leaves the VM up.
