#!/bin/sh
set -eu

FLAVOR="ec2-tpm"
cd /aports/main/linux-ec2-tpm

PACKAGES_DIR="/home/builder/packages/main/aarch64"

if ! ls /home/builder/.abuild/*.rsa /home/builder/.abuild/*.key >/dev/null 2>&1; then
  abuild-keygen -a -n
fi

# sanity check config is present
grep -q "^CONFIG_TCG_TPM=y" "./ec2-tpm.aarch64.config"
grep -q "^CONFIG_TCG_CRB=y" "./ec2-tpm.aarch64.config"
! grep -q "^CONFIG_SOUND=y" "./ec2-tpm.aarch64.config"
! grep -q "^CONFIG_SND" "./ec2-tpm.aarch64.config"

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
[ -f "/home/builder/.abuild/$keyname" ] || { echo "ERROR: missing /home/builder/.abuild/$keyname"; ls -la /home/builder/.abuild; exit 1; }

cp -f "/home/builder/.abuild/$keyname" "/out/$keyname"
ln -sf -- "$keyname" /out/linux-ec2-tpm-latest.pub
