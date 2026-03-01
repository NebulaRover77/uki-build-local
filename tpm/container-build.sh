#!/bin/sh
set -eu

FLAVOR="ec2-tpm"
cd /aports/main/linux-ec2-tpm

PACKAGES_DIR="/home/builder/packages/main/aarch64"

ABUILD_DIR="/home/builder/.abuild"
ABUILD_KEY_NAME="${ABUILD_KEY_NAME:-build-000001}"

# Your mounted long-lived key
PRIV="$ABUILD_DIR/${ABUILD_KEY_NAME}.rsa"
PUB="$ABUILD_DIR/${ABUILD_KEY_NAME}.rsa.pub"

# Alias name you want baked into the APK signature
ALIAS="build_key"
ALIAS_PRIV="$ABUILD_DIR/${ALIAS}.rsa"
ALIAS_PUB="$ABUILD_DIR/${ALIAS}.rsa.pub"

# Require real key material
[ -f "$PRIV" ] || { echo "ERROR: missing $PRIV"; exit 1; }
[ -f "$PUB"  ] || { echo "ERROR: missing $PUB";  exit 1; }

# Create/refresh alias filenames (same key material, different names)
cp -f "$PRIV" "$ALIAS_PRIV"
cp -f "$PUB"  "$ALIAS_PUB"
chmod 600 "$ALIAS_PRIV"
chmod 644 "$ALIAS_PUB"

# Pin abuild.conf to the alias private key so signing uses ALIAS_PUB name
printf 'PACKAGER_PRIVKEY="%s"\n' "$ALIAS_PRIV" > "$ABUILD_DIR/abuild.conf"

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

# export signing pubkey that matches the .SIGN.RSA.* inside the apk
sigfile="$(tar -tf "$apkfile" | awk '/^\.SIGN\.RSA\./ {print; exit}')"
[ -n "$sigfile" ] || { echo "ERROR: no .SIGN.RSA.* found in $apkfile"; exit 1; }

keyname="${sigfile#.SIGN.RSA.}"
[ -f "$ABUILD_DIR/$keyname" ] || {
  echo "ERROR: missing $ABUILD_DIR/$keyname" >&2
  ls -la "$ABUILD_DIR" >&2
  exit 1
}

# Keep the "true" key name around (optional, but good for debugging)
cp -f "$ABUILD_DIR/$keyname" "/out/$keyname"
ln -sf -- "$keyname" /out/linux-ec2-tpm-latest.pub

# Stable, canonical name for downstream consumers (AMI builder, prepare-target, etc.)
cp -f "$ABUILD_DIR/$keyname" /out/build_key.rsa.pub
