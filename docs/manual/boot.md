# Boot splash

kuwai ships a minimal [Plymouth](https://www.freedesktop.org/wiki/Software/Plymouth/) theme: a black screen, one ring in kuwai's pink that turns slowly (about one turn in ten seconds), and, when an encrypted disk asks for its passphrase, the lock screen's password pill (270 × 42, the same wash and edge) with five dots that ripple once per key and never show how long the passphrase is. When the prompt is answered the pill goes and the ring stays until the login screen takes over.

It lives in `system/plymouth/kuwai/` (`kuwai.plymouth`, `kuwai.script`, three small pictures). Installing it is a separate step you run yourself, because it changes your initramfs. Nothing else in kuwai touches it, and `system/install` and `greeter/install` are untouched.

## Before you install

Arch needs three things, and the installer checks the first two and tells you what is missing:

1. The `plymouth` package (`sudo pacman -S plymouth`).
2. The `plymouth` hook in `/etc/mkinitcpio.conf`, after `base udev`. For an encrypted root with the busybox `encrypt` hook it goes before `encrypt`; with `sd-encrypt` the hook order is `base systemd plymouth … sd-encrypt` (see the Arch wiki's Plymouth page). The installer never edits this file.
3. `quiet splash` on the kernel command line (GRUB: `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`, then `sudo grub-mkconfig -o /boot/grub/grub.cfg`; systemd-boot: the `options` line).

## Install

```sh
system/plymouth/install --dry-run   # what it would do; changes nothing
sudo system/plymouth/install        # copies the theme, makes it the default, rebuilds the initramfs
```

It copies the committed theme (refusing links and uncommitted changes; `--dirty` installs the working tree), records the theme that was the default, runs `plymouth-set-default-theme -R kuwai`, and prints the checksum of every file it installed. If the `plymouth` hook is missing from `mkinitcpio.conf` it still sets the default theme but skips the rebuild and tells you what to add; `--no-initramfs` skips the rebuild on purpose. Nothing changes on screen until the next boot.

To look at it before rebooting, from a text console (Ctrl+Alt+F3), not from the desktop:

```sh
sudo plymouthd --debug --debug-file=/tmp/plymouth.log
sudo plymouth --show-splash
sudo plymouth ask-for-password --prompt="Enter passphrase for cryptroot"
sudo plymouth quit
```

## Undo

```sh
sudo system/plymouth/install --undo
```

Puts back the theme that was the default (or Plymouth's own default if none was recorded), rebuilds the initramfs and removes `/usr/share/plymouth/themes/kuwai`. If you have since chosen another theme, only kuwai's files are removed.

## Another accent

The ring's colour is drawn into `ring.png`. `system/plymouth/make-assets --accent '#2f81f7'` redraws the three pictures (it needs Pillow; run it as yourself), then commit and install again. The default is the login screen's pink.

## What it was tried with

The theme's files and its installer are covered by tests that install into a fake root (`tests/system/test_plymouth_install.py`: files, modes, the `plymouth-set-default-theme -R kuwai` call, undo, links refused, dry run). The splash itself can only be seen at boot on your machine; if the ring turns too fast or too slow for your display, the step is the `0.0126` in `kuwai.script` (radians per refresh, at Plymouth's 50 a second).
