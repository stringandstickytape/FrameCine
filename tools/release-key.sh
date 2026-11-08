#!/usr/bin/env bash
# The release signing key (docs/packaging.md, "Releases"; docs/framedrop.md, "Our own updates"). Run from Git Bash.
#
#   tools/release-key.sh            make the key pair if there is none; write the public key into the app
#   tools/release-key.sh --check    only check: the private key is there, owner-only, and matches the app's public key
#
# The private key: $VRVP_RELEASE_KEY, default ~/.config/vrvp-release/release-key.pem (on Windows
# %USERPROFILE%\.config\vrvp-release\release-key.pem). RSA-3072, PEM. It never goes in the repository, and nothing
# here prints it. Keep a copy offline: without it no later release can be signed, and every installed player refuses
# an update signed with another key. (To change keys, ship the new public key in a release signed with the old one.)
# The public key: app/update/release-key.pub.pem (committed). The player checks latest.json.sig with it.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
KEY=${VRVP_RELEASE_KEY:-$HOME/.config/vrvp-release/release-key.pem}
PUB="$REPO/app/update/release-key.pub.pem"
CHECK=0
case "${1:-}" in
  "") ;;
  --check) CHECK=1 ;;
  -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
  *) echo "unknown argument: $1" >&2; exit 2 ;;
esac
command -v openssl > /dev/null || { echo "needs openssl (Git Bash has it)" >&2; exit 1; }

owner_only() {  # chmod 600; on a Windows disk also the ACL, which is what counts there
  chmod 600 "$1"
  if command -v icacls.exe > /dev/null 2>&1 && [ -n "${USERNAME:-}" ]; then
    MSYS2_ARG_CONV_EXCL='*' icacls.exe "$(cygpath -w "$1")" /inheritance:r /grant:r "${USERNAME}:F" > /dev/null
  fi
}

pub_of_key() { openssl pkey -in "$KEY" -pubout 2> /dev/null; }

if [ "$CHECK" = 1 ]; then
  [ -f "$KEY" ] || { echo "no private key at $KEY (run tools/release-key.sh)" >&2; exit 1; }
  [ -f "$PUB" ] || { echo "no public key at app/update/release-key.pub.pem" >&2; exit 1; }
  BITS=$(openssl pkey -in "$KEY" -noout -text 2> /dev/null | head -1 | grep -o '[0-9]\+ bit' || true)
  [ "$BITS" = "3072 bit" ] || { echo "the private key is not RSA-3072" >&2; exit 1; }
  [ "$(pub_of_key)" = "$(openssl pkey -pubin -in "$PUB" 2> /dev/null)" ] ||
    { echo "app/update/release-key.pub.pem is not the public half of $KEY" >&2; exit 1; }
  echo "release key: ok (RSA-3072; the app's public key matches)"
  exit 0
fi

if [ -f "$KEY" ]; then
  echo "private key already at $KEY: kept"
else
  mkdir -p "$(dirname "$KEY")"
  chmod 700 "$(dirname "$KEY")"
  (umask 077 && openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$KEY" 2> /dev/null)
  owner_only "$KEY"
  echo "made a new RSA-3072 private key at $KEY (owner only). Keep a copy offline."
fi

mkdir -p "$(dirname "$PUB")"
NEW=$(pub_of_key)
[ -n "$NEW" ] || { echo "can't read $KEY" >&2; exit 1; }
if [ -f "$PUB" ] && [ "$NEW" = "$(openssl pkey -pubin -in "$PUB" 2> /dev/null)" ]; then
  echo "app/update/release-key.pub.pem: already the matching public key"
else
  [ ! -f "$PUB" ] || echo "app/update/release-key.pub.pem: replaced (it was not this key's public half)" >&2
  printf '%s\n' "$NEW" > "$PUB"
  echo "wrote the public key to app/update/release-key.pub.pem: commit it"
fi
openssl pkey -pubin -in "$PUB" -outform DER 2> /dev/null | sha256sum | cut -c1-16 | sed 's/^/public key fingerprint (SHA-256 of the DER, first 16): /'
