#!/bin/sh
set -eu

KEY_OUT=/out/linux-ec2-tpm-latest.pub

FLAVOR="${FLAVOR:-ec2-tpm}"
SKIP_DEV_DOC="${SKIP_DEV_DOC:-1}"
DROP_FIRMWARE_DEP="${DROP_FIRMWARE_DEP:-1}"

cd /aports/main/linux-lts
APKBUILD="./APKBUILD"
CFG="/host/ec2-tpm.aarch64.config"

# ---- bring in our flavor config ----
cp "$CFG" "./${FLAVOR}.aarch64.config"
CFG_LOCAL="./${FLAVOR}.aarch64.config"

echo "==== sanity check (input config) ===="
grep -q "^CONFIG_TCG_TPM=y" "$CFG_LOCAL"
grep -q "^CONFIG_TCG_CRB=y" "$CFG_LOCAL"
! grep -q "^CONFIG_SOUND=y" "$CFG_LOCAL"
! grep -q "^CONFIG_SND" "$CFG_LOCAL"

# ---- patch APKBUILD locally (no need to maintain the builder image) ----
if [ "$DROP_FIRMWARE_DEP" = "1" ]; then
  # Prefer: remove firmware dep only for this flavor’s function if it exists.
  # e.g. ec2-tpm() { ... }
  if grep -qE "^${FLAVOR}\(\)[[:space:]]*\{" "$APKBUILD"; then
    # Within the function body, delete any line that appends linux-firmware-any
    # (simple but effective: remove that token on lines setting depends=)
    sed -i "/^${FLAVOR}()[[:space:]]*{/,/^[[:space:]]*}/ s/\<linux-firmware-any\>//g" "$APKBUILD"
  else
    # Fallback: remove the global append in package()
    sed -i \
      -e '/^[[:space:]]*depends="\$depends[[:space:]]\+linux-firmware-any"[[:space:]]*$/d' \
      -e '/^[[:space:]]*depends="\$depends[[:space:]]*linux-firmware-any[[:space:]]*"[[:space:]]*$/d' \
      "$APKBUILD"
  fi

  # Remove from makedepends too (builder doesn’t need to fetch it)
  sed -i -e 's/\<linux-firmware-any\>//g' "$APKBUILD"

  if grep -q 'linux-firmware-any' "$APKBUILD"; then
    echo "ERROR: linux-firmware-any still present in APKBUILD after patch:"
    grep -n 'linux-firmware-any' "$APKBUILD" || true
    exit 1
  fi
fi

if [ "$SKIP_DEV_DOC" = "1" ]; then
  # Prevent doc copying into the main package (keeps kernel apk lean)
  if ! grep -q 'return 0 # no-doc' "$APKBUILD"; then
    sed -i '/_package "\$_flavor" "\$pkgdir"/a\
  return 0 # no-doc\
' "$APKBUILD"
  fi

  # Don’t build -dev/-doc (safer than blanking subpackages)
  # Replace the initial subpackages assignment line with just the main package.
  sed -i 's/^subpackages="[^"]*"/subpackages=""/' "$APKBUILD"
fi

echo "==== building flavor: $FLAVOR ===="
FLAVOR="$FLAVOR" abuild checksum
FLAVOR="$FLAVOR" abuild -r

apkfile="$(ls -1t /home/builder/packages/main/aarch64/linux-"$FLAVOR"-[0-9]*.apk | head -n 1)"
echo "==== wrote version: $(basename "$apkfile") ===="
echo "==== kernel release(s) in apk ===="
tar -tf "$apkfile" | awk -F/ '$1=="lib" && $2=="modules" && $3!="" {print $3}' | sort -u

tmp="/out/$(basename "$apkfile").new"
final="/out/$(basename "$apkfile")"

cp -f "$apkfile" "$tmp"
echo "==== verifying archive ===="
tar -tf "$tmp" | head
mv -f "$tmp" "$final"

ln -sf "$(basename "$final")" /out/linux-ec2-tpm-latest.apk

sigfile="$(tar -tf "$final" | awk '/^\.SIGN\.RSA\./ {print; exit}')"
[ -n "$sigfile" ] || { echo "ERROR: no .SIGN.RSA.* file found in $final"; exit 1; }

keyname="${sigfile#.SIGN.RSA.}"
if [ ! -f "/etc/apk/keys/$keyname" ]; then
  echo "ERROR: expected key /etc/apk/keys/$keyname not found"
  ls -la /etc/apk/keys
  exit 1
fi

cp -f "/etc/apk/keys/$keyname" "/out/$keyname"
ln -sf -- "$keyname" "$KEY_OUT"
echo "==== wrote pubkey: $KEY_OUT -> $keyname ===="

echo "==== final runtime deps in produced apk (.PKGINFO) ===="
tar -xOf /out/linux-ec2-tpm-latest.apk .PKGINFO | grep '^depend = ' || true
