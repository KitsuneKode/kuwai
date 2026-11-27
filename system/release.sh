# shellcheck shell=bash
KUWAI_LIB=/usr/local/lib/kuwai
[ "$(id -u)" = 0 ] || KUWAI_LIB=${KUWAI_SYSROOT:-}/usr/local/lib/kuwai

from_release() {
    local tree=$1 trust=$2 self=$3 releases
    tree=$(readlink -f -- "$tree")
    if [ "$trust" = 1 ]; then
        echo "--trust-clone: installing from $tree as it is. That trusts every file in it; nothing was checked." >&2
        return 0
    fi
    releases=$(readlink -f -- "$KUWAI_LIB/releases" 2>/dev/null || true)
    case $tree in
        "${releases:-/nonexistent}"/v[0-9]*) ;;
        *)
            cat >&2 <<REFUSE
This copy of kuwai is one your account can change, so root doesn't install from it.
Install a signed release first (kuwai setup), then run the same command from root's checked copy:
  sudo $KUWAI_LIB/current/$self
Developing kuwai? --trust-clone installs this copy as it is, trusting every file in it.
REFUSE
            exit 1 ;;
    esac
    /usr/bin/python3 -I "$tree/bin/kuwai-verify" check "$tree" >/dev/null \
        || { echo "Root's copy of kuwai isn't the signed release any more; nothing was installed." >&2; exit 1; }
}
