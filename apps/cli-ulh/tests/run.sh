#!/bin/bash
# ulh tests - run on Linux:  bash apps/cli-ulh/tests/run.sh
#
# Runs every *.test.sh in this folder against a copy of ulh in a temporary
# folder. sudo, package managers and the network are stubs: nothing gets
# installed, nothing outside the temporary folder changes.
set -u

# Run with bash, never with sh. Under dash ${BASH_SOURCE[0]} is empty, dirname
# turns that into ".", and SRC becomes "/" three levels up - the copy below
# then takes the WHOLE file system into the temporary folder. On a WSL machine
# that is /mnt/c as well, and /tmp is a 32 GB tmpfs: measured on 16.10.2026 it
# filled up with 13 and 19 GB, after which apt reported OpenPGP signature
# errors ("Splitting up ... into data and signature failed") that had nothing
# to do with signatures. So the shell is checked first, and SRC afterwards.
if [ -z "${BASH_VERSION:-}" ]; then
    echo "run.sh needs bash, not sh: bash apps/cli-ulh/tests/run.sh" >&2
    exit 2
fi

TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "${TESTS}/../../.." && pwd)"          # the ulh folder

# SRC has to BE the ulh folder, not something above it. Two files that only
# this repository has; without them nothing is copied anywhere.
if [ ! -f "${SRC}/apps/cli-ulh/ulh.sh" ] && [ ! -f "${SRC}/apps/cli-ulh/classes/bootstrap.sh" ]; then
    echo "run.sh: ${SRC} is not the ulh folder - refusing to copy it" >&2
    exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASSED=0
FAILED=0

# check "what" command... - one line per check
check() {
    if "${@:2}" >/dev/null 2>&1; then
        PASSED=$((PASSED + 1)); echo "  ok    $1"
    else
        FAILED=$((FAILED + 1)); echo "  FAIL  $1"
    fi
}
not() { ! "$@"; }

# name_fits / name_differs read the SENTENCE that "openssl x509 -checkhost" and
# "-checkip" print, never their exit code. Measured on 4.11.2026 with one
# certificate for CN=a.example.org, asked for b.example.org:
#
#   OpenSSL 3.0.2 / 3.0.13 / 3.0.22  ->  exit 0, "... does NOT match certificate"
#   OpenSSL 3.5.7                    ->  exit 1, same sentence
#
# Below 3.5 the tool says the verdict and does not signal it. So "not openssl
# ... -checkhost <foreign>" could NEVER pass there - and, worse, the positive
# assertion next to it passed for EVERY name and measured nothing. Both halves
# are read from the output now, and both are positive assertions: each one
# names the sentence it wants, so neither can be satisfied by silence.
_cert_said() { openssl x509 -in "$1" -noout "$2" "$3" 2>/dev/null; }
name_fits()    { _cert_said "$1" -checkhost "$2" | grep -q 'does match certificate'; }
name_differs() { _cert_said "$1" -checkhost "$2" | grep -q 'does NOT match certificate'; }
addr_fits()    { _cert_said "$1" -checkip   "$2" | grep -q 'does match certificate'; }
addr_differs() { _cert_said "$1" -checkip   "$2" | grep -q 'does NOT match certificate'; }

# ---------------------------------------------------------------- stubs
STUBS="${TMP}/stubs"
mkdir -p "$STUBS"
for p in apt-get apt dnf yum pacman zypper apk snap systemctl service flatpak clear; do
    printf '#!/bin/bash\nexit 0\n' > "${STUBS}/${p}"
done
printf '#!/bin/bash\necho "no network in tests" >&2\nexit 4\n' > "${STUBS}/wget"
cp "${STUBS}/wget" "${STUBS}/curl"
printf '#!/bin/bash\nwhile [[ "${1:-}" == -* ]]; do shift; done\nexec "$@"\n' > "${STUBS}/sudo"
chmod +x "$STUBS"/*
export PATH="${STUBS}:${PATH}" TERM=dumb HOME="${TMP}/home"
mkdir -p "$HOME"
# English, whatever language the test machine speaks
export LANG=C.UTF-8 ULH_SYS_LOCALE=en_US.UTF-8
unset LC_ALL LC_MESSAGES ULH_LANG
export GIT_CONFIG_GLOBAL="${TMP}/gitconfig"
printf '[user]\n\tname = ulh test\n\temail = test@example.invalid\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"

# ---------------------------------------------------------------- ulh under test
# upstream = this ulh as a git repository, remote.git = "GitHub", ULH = installed copy
UP="${TMP}/upstream"
mkdir -p "$UP"
if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
    ( cd "$SRC" && git ls-files -co --exclude-standard -z | xargs -0 cp --parents -t "$UP" 2>/dev/null )
else
    cp -r "$SRC/." "$UP/"
    rm -rf "$UP/apps/cli-ulh/data" "$UP/apps/cli-ulh/config/repo.yaml" "$UP/apps/cli-ulh/config/answer.yaml" \
           "$UP/apps/cli-ulh/config/settings.yaml"
fi
git -C "$UP" init -q
git -C "$UP" add -A
git -C "$UP" commit -qm "ulh under test"
git clone -q --bare "$UP" "${TMP}/remote.git"
ULH="${TMP}/ulh"
git clone -q "${TMP}/remote.git" "$ULH"

case "$(uname -m)" in
    x86_64)        YQ="${ULH}/apps/cli-ulh/vendor/yq/yq-amd64" ;;
    aarch64|arm64) YQ="${ULH}/apps/cli-ulh/vendor/yq/yq-arm64" ;;
    armv7l)        YQ="${ULH}/apps/cli-ulh/vendor/yq/yq-arm" ;;
    *)             YQ="${ULH}/apps/cli-ulh/vendor/yq/yq-386" ;;
esac

# ---------------------------------------------------------------- run
for t in "$TESTS"/*.test.sh; do
    echo "$(basename "$t" .test.sh)"
    source "$t"
done

echo ""
echo "passed: ${PASSED}  failed: ${FAILED}"
(( FAILED == 0 ))
