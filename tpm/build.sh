#!/bin/sh
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

ALPINE_VER="${ALPINE_VER:-3.23}"
OUT_DIR="${OUT_DIR:-$REPO_DIR/private/kernel/out}"

mkdir -p "$OUT_DIR"

docker build \
  -t "alpine-ec2-tpm-builder:${ALPINE_VER}" \
  --build-arg "ALPINE_VER=${ALPINE_VER}" \
  -f "$SCRIPT_DIR/Dockerfile" \
  "$SCRIPT_DIR"

docker run --rm -it \
  -u builder \
  -v "$SCRIPT_DIR":/host \
  -v "$OUT_DIR":/out \
  -v alpine-ec2-tpm-ccache:/home/builder/.cache/ccache \
  "alpine-ec2-tpm-builder:${ALPINE_VER}" \
  /bin/sh /host/container-build.sh

# ---- write build manifest for reproducibility/debugging ----
set -eu

APK="$(ls -1t "$OUT_DIR"/linux-ec2-tpm-*.apk 2>/dev/null | head -n 1)"
[ -n "$APK" ] && [ -f "$APK" ] || {
  echo "ERROR: no '$OUT_DIR'/linux-ec2-tpm-*.apk found" >&2
  exit 1
}

CFG="$(tar -tf "$APK" | awk -F/ '$1=="boot" && $2 ~ /^config-/ {print $1"/"$2; exit}')"
MODREL="$(tar -tf "$APK" | awk -F/ '$1=="lib" && $2=="modules" && $3!="" {print $3; exit}')"

[ -n "$CFG" ] || {
  echo "ERROR: no boot/config-* found inside $(basename "$APK")" >&2
  tar -tf "$APK" | head -n 50 >&2
  exit 1
}

[ -n "$MODREL" ] || {
  echo "ERROR: no lib/modules/<release>/ found inside $(basename "$APK")" >&2
  tar -tf "$APK" | awk -F/ '$1=="lib"&&$2=="modules"{print}' | head -n 50 >&2
  exit 1
}

APK_SHA="$(shasum -a 256 "$APK" | awk '{print $1}')"
CFG_SHA="$(tar -xOf "$APK" "$CFG" | shasum -a 256 | awk '{print $1}')"

# Optional: capture aports branch + flavor (helps explain version drift later)
FLAVOR="${FLAVOR:-ec2-tpm}"

MANIFEST="$OUT_DIR/manifest.txt"
{
  echo "apk=$(basename "$APK")"
  echo "apk_sha256=$APK_SHA"
  echo "alpine_ver=$ALPINE_VER"
  echo "flavor=$FLAVOR"
  echo "config_path=$CFG"
  echo "config_sha256=$CFG_SHA"
  echo "modules_release=$MODREL"
} > "$MANIFEST"

# Guardrail: ensure modules_release is really present (avoids “success with blank value”)
grep -q '^modules_release=.' "$MANIFEST" || {
  echo "ERROR: modules_release missing" >&2
  cat "$MANIFEST" >&2
  exit 1
}

echo "Wrote: $MANIFEST"
