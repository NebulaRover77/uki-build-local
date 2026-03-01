#!/usr/bin/env bash
set -euo pipefail

# Create a long-lived Alpine abuild signing key under:
#   <repo-root>/private/abuildkeys/
# Then rename it to build-000001.rsa (+ .pub) and pin it in abuild.conf.
#
# Usage:
#   ./scripts/init-abuild-key.sh
# Optional env:
#   IMAGE=alpine-ec2-tpm-builder:3.23 KEY_NAME=build-000001 KEY_SUBDIR=private/abuildkeys

IMAGE="${IMAGE:-alpine-ec2-tpm-builder:3.23}"
KEY_NAME="${KEY_NAME:-build-000001}"
KEY_SUBDIR="${KEY_SUBDIR:-private/abuildkeys}"

# Resolve repo root as: git root if available, else directory containing this script's parent (../)
if REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
fi

HOST_KEY_DIR="$REPO_ROOT/$KEY_SUBDIR"
CONTAINER_KEY_DIR="/home/builder/.abuild"

mkdir -p "$HOST_KEY_DIR"
chmod 700 "$HOST_KEY_DIR"

target_priv="$HOST_KEY_DIR/$KEY_NAME.rsa"
target_pub="$HOST_KEY_DIR/$KEY_NAME.rsa.pub"
conf_file="$HOST_KEY_DIR/abuild.conf"

# If key already exists, just ensure abuild.conf is correct and exit.
if [[ -f "$target_priv" && -f "$target_pub" ]]; then
  printf 'PACKAGER_PRIVKEY="%s/%s.rsa"\n' "$CONTAINER_KEY_DIR" "$KEY_NAME" > "$conf_file"
  chmod 600 "$target_priv"
  chmod 644 "$target_pub" "$conf_file"
  echo "OK: Key already exists: $KEY_SUBDIR/$KEY_NAME.rsa"
  exit 0
fi

# Guardrail: don't overwrite an existing target name.
if [[ -e "$target_priv" || -e "$target_pub" ]]; then
  echo "ERROR: $KEY_SUBDIR/$KEY_NAME.rsa or .pub already exists; refusing to overwrite." >&2
  exit 1
fi

echo "Repo root:   $REPO_ROOT"
echo "Key dir:     $HOST_KEY_DIR"
echo "Using image: $IMAGE"
echo "Generating abuild key..."

docker run --rm -t -u builder \
  -v "$HOST_KEY_DIR:$CONTAINER_KEY_DIR" \
  "$IMAGE" \
  abuild-keygen -a -n

# Find newest generated keypair (random-ish name like -69a38d75.rsa)
new_priv="$(ls -1t "$HOST_KEY_DIR"/*.rsa | head -n 1)"
new_base="$(basename "$new_priv" .rsa)"

[[ -f "$HOST_KEY_DIR/$new_base.rsa" ]] || { echo "ERROR: missing generated private key" >&2; exit 1; }
[[ -f "$HOST_KEY_DIR/$new_base.rsa.pub" ]] || { echo "ERROR: missing generated public key" >&2; exit 1; }

echo "Renaming:"
echo "  $new_base.rsa     -> $KEY_NAME.rsa"
echo "  $new_base.rsa.pub -> $KEY_NAME.rsa.pub"
mv -v "$HOST_KEY_DIR/$new_base.rsa"     "$target_priv"
mv -v "$HOST_KEY_DIR/$new_base.rsa.pub" "$target_pub"

# Pin the signing key for abuild
printf 'PACKAGER_PRIVKEY="%s/%s.rsa"\n' "$CONTAINER_KEY_DIR" "$KEY_NAME" > "$conf_file"

# Tighten perms
chmod 600 "$target_priv"
chmod 644 "$target_pub" "$conf_file"

echo
echo "Done."
echo "  Private key: $KEY_SUBDIR/$KEY_NAME.rsa"
echo "  Public  key: $KEY_SUBDIR/$KEY_NAME.rsa.pub"
echo "  Config    : $KEY_SUBDIR/abuild.conf"
echo
echo "Reminder (trust): copy the public key into /etc/apk/keys in any environment that must verify installs:"
echo "  sudo cp $KEY_SUBDIR/$KEY_NAME.rsa.pub /etc/apk/keys/"
