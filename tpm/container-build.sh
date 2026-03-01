#!/bin/sh
set -eu

FLAVOR="ec2-tpm"
cd /aports/main/linux-ec2-tpm

PACKAGES_DIR="/home/builder/packages/main/aarch64"

ABUILD_KEY_NAME="${ABUILD_KEY_NAME:-build-000001}"
ABUILD_DIR="/home/builder/.abuild"
PRIV="$ABUILD_DIR/${ABUILD_KEY_NAME}.rsa"

# Require the long-lived key (do not auto-generate random keys)
[ -f "$PRIV" ] || {
  echo "ERROR: missing $PRIV (expected long-lived abuild key)" >&2
  ls -la "$ABUILD_DIR" >&2 || true
  exit 1
}

# Create/pin abuild.conf locally inside the container (no host mount needed)
CONF="$ABUILD_DIR/abuild.conf"
if [ ! -f "$CONF" ] || ! grep -q "PACKAGER_PRIVKEY=\"$PRIV\"" "$CONF" 2>/dev/null; then
  printf 'PACKAGER_PRIVKEY="%s"\n' "$PRIV" > "$CONF"
fi

FLAVOR="$FLAVOR" abuild checksum

# Clean stale package artifacts before building. A persistent abuild key volume can
# rotate signing keys over time, and stale APKs signed by old keys may cause
# `abuild -r` to fail with "UNTRUSTED signature" while updating the local index.
mkdir -p "$PACKAGES_DIR"
find "$PACKAGES_DIR" -maxdepth 1 -name 'linux-ec2-tpm-*.apk' -delete
rm -f "$PACKAGES_DIR"/APKINDEX.tar.gz "$PACKAGES_DIR"/*.SIGN.RSA.*

FLAVOR="$FLAVOR" abuild -r

apkfile="$(ls -1t "$PACKAGES_DIR"/linux-ec2-tpm-[0-9]*.apk | head -n 1)"

# copy apk out
cp -f "$apkfile" "/out/$(basename "$apkfile")"
ln -sf "$(basename "$apkfile")" /out/linux-ec2-tpm-latest.apk
