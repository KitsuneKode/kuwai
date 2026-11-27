#!/bin/bash
set -uo pipefail
pacman -Sy --noconfirm --needed git python gnupg sudo rsync diffutils >/dev/null 2>&1 || { echo "pacman failed"; exit 2; }
useradd -m tester
results=()
pass() { results+=("PASS  $1"); }
fail() { results+=("FAIL  $1"); }
check() { local name=$1; shift; if "$@" >/tmp/check.out 2>&1; then pass "$name"; else fail "$name"; sed 's/^/    /' /tmp/check.out | tail -8; fi; }
refuses() { local name=$1; shift; if "$@" >/tmp/check.out 2>&1; then fail "$name (it ran)"; else pass "$name"; fi; }

su - tester -c '
set -euo pipefail
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -m700 ~/.gnupg
gpg --batch --quiet --passphrase "" --quick-gen-key "Release <r@example.invalid>" ed25519 sign never 2>/dev/null
gpg --batch --quiet --passphrase "" --quick-gen-key "Other <o@example.invalid>" ed25519 sign never 2>/dev/null
gpg --with-colons --fingerprint Release | awk -F: "\$1==\"fpr\"{print \$10; exit}" > ~/fpr
gpg --with-colons --fingerprint Other | awk -F: "\$1==\"fpr\"{print \$10; exit}" > ~/other
mkdir ~/src && tar -xf /kuwai-src.tar -C ~/src
gpg --export --armor "$(cat ~/fpr)" > ~/src/release-signers/release.asc
cd ~/src && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@e commit -qm release
d=$(bin/kuwai-verify manifest-rev . HEAD)
git -c user.name=t -c user.email=t@e tag -s -u "$(cat ~/fpr)" -m "kuwai 0.2.0" -m "kuwai-tree-sha256 $d" v0.2.0
bin/kuwai-verify fetch ~/src v0.2.0 --signers ~/src/release-signers --into ~/.cache/kuwai/releases/v0.2.0 > ~/info.json
'
H=/home/tester
STAGE=$H/.cache/kuwai/releases/v0.2.0
FPR=$(cat $H/fpr)
DIGEST=$(python3 -c 'import json;print(json.load(open("/home/tester/info.json"))["digest"])')
VERIFY=$H/src/bin/kuwai-verify
LIB=/usr/local/lib/kuwai
mkdir -p /tmp/stubs
printf '#!/bin/sh\necho "$*" >> /tmp/systemctl.log\nexit 0\n' > /tmp/stubs/systemctl
printf '#!/bin/sh\n[ "$1" = -Qoq ] && exit 1\nexit 0\n' > /tmp/stubs/pacman
chmod 755 /tmp/stubs/*
export PATH=/tmp/stubs:$PATH SUDO_USER=tester

cp $STAGE/system/kuwai.desktop /tmp/desktop.orig
echo "# planted" >> $STAGE/system/kuwai.desktop
refuses "root refuses a staged copy changed after the user checked it" /usr/bin/python3 -I $VERIFY install --from $STAGE --tag-file $STAGE/.git/kuwai-release.tag --name v0.2.0 --digest $DIGEST --signer $FPR
cp /tmp/desktop.orig $STAGE/system/kuwai.desktop
chown tester: $STAGE/system/kuwai.desktop
refuses "nothing was left behind by the refusal" test -e $LIB/current
refuses "root refuses a key it wasn't given" /usr/bin/python3 -I $VERIFY install --from $STAGE --tag-file $STAGE/.git/kuwai-release.tag --name v0.2.0 --digest $DIGEST --signer "$(cat $H/other)"
check "root installs its own checked copy" /usr/bin/python3 -I $VERIFY install --from $STAGE --tag-file $STAGE/.git/kuwai-release.tag --name v0.2.0 --digest $DIGEST --signer $FPR
check "root's copy is root's alone" bash -c "[ \"\$(find $LIB ! -user root | wc -l)\" = 0 ] && [ \"\$(find $LIB -perm /022 ! -type l | wc -l)\" = 0 ]"
check "root's check passes" /usr/bin/python3 -I $LIB/current/bin/kuwai-verify check $LIB/current
refuses "the login entry refuses to install from the clone" $H/src/system/session
refuses "the clone refusal installed nothing" test -e /usr/local/bin/kuwai-session
check "the login entry installs from root's copy" $LIB/current/system/session
check "the login entry is root's" bash -c '[ "$(stat -c %U /usr/local/bin/kuwai-session)" = root ] && cmp -s /usr/local/bin/kuwai-session /usr/local/lib/kuwai/current/bin/kuwai-session'
check "the login entry check (as the user) agrees" su tester -c "$LIB/current/system/session --check"
check "the login entry undo from root's copy" bash -c "$LIB/current/system/session --undo && [ ! -e /usr/local/bin/kuwai-session ]"
check "the clone installs with --trust-clone, saying so" bash -c "$H/src/system/session --trust-clone 2>&1 | grep -q 'trusts every file' && $H/src/system/session --undo --trust-clone"
refuses "the wake helper refuses the clone" $H/src/system/install
check "the wake helper installs from root's copy" bash -c "$LIB/current/system/install && [ \"\$(stat -c %U /usr/local/libexec/kuwai-wake-root)\" = root ]"
check "the update helper is placed from root's copy" bash -c "/usr/bin/python3 -I $LIB/current/bin/kuwai-verify place update-helper && cmp -s $LIB/kuwai-update-root $H/src/bin/kuwai-update-root && [ \"\$(stat -c %U:%a $LIB/kuwai-update-root)\" = root:755 ]"
check "the password prompt is placed from root's copy" bash -c "/usr/bin/python3 -I $LIB/current/bin/kuwai-verify place auth-prompt && diff -r /usr/local/share/kuwai/shell-auth $H/src/shell-auth && [ \"\$(find /usr/local/share/kuwai ! -user root | wc -l)\" = 0 ]"

mkdir -p /etc/pam.d /etc/systemd/system/getty@tty1.service.d
echo "old pam" > /etc/pam.d/greetd
echo "autologin" > /etc/systemd/system/getty@tty1.service.d/override.conf
ln -sf /usr/lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service
refuses "the login screen refuses the clone" $H/src/greeter/install --yes
check "the login screen installs from root's copy" $LIB/current/greeter/install --yes
check "its receipt is root's, 0600" bash -c '[ "$(stat -c %U:%a /var/lib/kuwai-greeter/original/receipt)" = root:600 ] && grep -q "^restore	/etc/pam.d/greetd	pam-greetd	" /var/lib/kuwai-greeter/original/receipt'
check "its code is root's" bash -c '[ "$(find /var/lib/kuwai-greeter -path /var/lib/kuwai-greeter/home -prune -o ! -user root -print | wc -l)" = 0 ]'
check "undo restores what the receipt lists" bash -c "$LIB/current/greeter/install --undo && [ \"\$(cat /etc/pam.d/greetd)\" = 'old pam' ] && [ \"\$(cat /etc/systemd/system/getty@tty1.service.d/override.conf)\" = autologin ] && [ ! -e /etc/greetd/config.toml ] && grep -q 'enable sddm.service' /tmp/systemctl.log"
check "a second install keeps the first record" bash -c "$LIB/current/greeter/install --yes && [ \"\$(wc -l < /var/lib/kuwai-greeter/original/receipt)\" = 4 ]"
rm /var/lib/kuwai-greeter/original/receipt
refuses "undo without the receipt restores nothing" $LIB/current/greeter/install --undo
check "the kuwai pam file stayed" grep -q pam_keyinit /etc/pam.d/greetd

echo "# planted" >> $LIB/releases/v0.2.0/system/kuwai.desktop
refuses "root's copy, changed by root afterwards, is refused" $LIB/current/system/session
refuses "and nothing is placed from it" /usr/bin/python3 -I $LIB/current/bin/kuwai-verify place update-helper

printf '\n%s\n' "${results[@]}"
printf '%s\n' "${results[@]}" | grep -q '^FAIL' && exit 1
exit 0
