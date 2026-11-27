# Security

kuwai runs as your user session: a Hyprland config, a Quickshell shell, user
services, and an optional local assistant. Some parts touch sensitive things:
the lock screen, notification bodies, clipboard history, screen-share privacy,
the assistant's file and sandbox tools, and one root helper (`bin/kuwai-update-root`,
reached through pkexec for system updates).

## Reporting

Please report vulnerabilities privately through GitHub's
[private vulnerability reporting](https://github.com/KitsuneKode/kuwai/security/advisories/new),
not a public issue. Say what you did, what happened, and the commit you ran.

## What is verified before anything runs

- **Releases.** A release is a tag `vX.Y.Z` signed with `git tag -s` by a key in
  [`release-signers/`](release-signers/README), whose message carries
  `kuwai-tree-sha256`: the SHA-256 of every file in the tree (path, executable bit,
  content, link target). `kuwai release` makes exactly that.
- **Installing (`bin/kuwai-setup`).** Fetches only that tag into a new folder of its own,
  then checks it with `git verify-tag` against a keyring built from `release-signers/*.asc`
  alone, in a temporary `GNUPGHOME` (your own keyring plays no part), checks the tag's name
  and that the tree's digest is the signed one, checks the checked-out files again, and only
  then runs that release's `install.sh`. An unsigned tag, a plain tag, a tag signed by any
  other key, a tag without the digest or with another tree's, or a tag renamed from another
  release is refused, and nothing from it runs. With no key in `release-signers/`, everything
  is refused.
- **What root runs.** Root installs only from its own copy,
  `/usr/local/lib/kuwai/releases/vX.Y.Z` (owned by root, writable by no one else). Root makes
  that copy from the checked folder, then checks the copy itself: `gpgv` on the tag against
  the fingerprints root keeps in `/usr/local/lib/kuwai/signers/fingerprints`, and the digest
  of every file. A file changed after `kuwai-setup` checked it, a swapped tag, a key root
  doesn't trust, an older release than root's, a name with a control character in it, or a
  link out of the tree is refused, and nothing is installed.
- **What root's re-check protects, and what it can't.** It protects against the checked
  folder (anything running as you can write it) being changed between `kuwai-setup`'s check
  and root's copy: root checks what it copied, not what was checked. Once root has a release,
  the check runs root's own verifier (`/usr/local/lib/kuwai/current/bin/kuwai-verify`, used
  only when it and every folder above it are root's and writable by no one else) against
  the keys root keeps, so a changed `kuwai-verify` or `release-signers/` in your account
  can't choose what root trusts. A changed `kuwai-setup` still can, like any script you run
  that calls `sudo`: it chooses what runs as root. It can't protect the first install from a changed `kuwai-setup`: that run names the keys
  and supplies the verifier root runs, and both come from your account. Check the
  fingerprint it prints against the published one before the first `sudo`.
- **Root's release keys.** `kuwai-setup` names the release keys to root only at the first
  install. After that, each release root takes replaces root's list with the keys listed in
  that release's `release-signers/`, and only after its tag checked out against a key
  already on the list: a key is added by a release the old key signs, and removed by the
  next one, which the new key signs. A tag signed by a removed key is refused, and it can't
  be named back in. The list is written in one step, before root's current release changes.
  A release older than root's can only drop keys. [`release-signers/README`](release-signers/README)
  has the steps.
  `system/session`, `system/install`, `greeter/install`, `kuwai auth pin` and
  `kuwai update install-helper` run from that copy only, and check it again each time
  (ownership of every folder and file, signature, digest). From a clone they refuse unless
  given `--trust-clone`, which says that it trusts every file in the clone.
- **Updates.** `kuwai update-self` checks a release the same way before stable moves.
  The root update helper's password prompt names the whole transaction: the number of Arch
  packages and the digest of exactly which versions, the held packages, the build
  dependencies and the AUR packages. Root runs that and nothing else; if pacman resolves a
  different set after it syncs, nothing is installed.
- **Undoing the login screen.** `greeter/install --undo` restores only what the root-owned
  receipt written at install lists (paths it replaced, each kept copy's digest, the earlier
  login manager). An install from before receipts has none: then, only if every folder from
  `/` down to the kept copies and each copy is root's and writable by no one else, it first
  records what is kept there, and follows that. Otherwise it restores nothing.

What only a real install shows: `sudo`/`pkexec` and polkit on the machine, the real
`/usr/local` ownership, greetd booting into the login screen.

## What is covered by tests

- The assistant: secrets are refused by read *and* by search; files the sandbox
  container can write are opened without following links
  (`tests/agent/test_file_policy.py`, `tests/agent/test_sandbox_boundary.py`).
- The root helper refuses bad paths, names and symlinks before touching anything
  (`tests/root`). No privileged transaction runs in tests.
- The installer restores the state before the first install and never writes
  through a link (`tests/install`).
- Releases: every refusal above, and nothing from a refused release running
  (`tests/release/test_provenance.py`); root's copy and its checks, run under a stand-in
  root (`tests/release/test_root_copy.py`); the login screen's receipt
  (`tests/greeter/test_receipt.py`); the update prompt's transaction
  (`tests/root/test_update_root.py`, `tests/update/test_root_helper_trust.py`);
  `update-self` and `kuwai release` (`tests/recovery/test_release_refs.py`).

What is *not* qualified yet: live lock-screen failure modes, real portal screen
sharing, and the assistant on hardware other than the author's. See
[`docs/manual/security.md`](docs/manual/security.md) for the known gaps.
