#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

ALPINE_VER="${ALPINE_VER:-3.23}"
BUILD_ID="$(git -C "$REPO_DIR" describe --tags --always --dirty 2>/dev/null || echo unknown)"
OUT_DIR="${OUT_DIR:-$REPO_DIR/private/uki-build-$(BUILD_ID)/kernel}"
GIT_HEAD="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"

# ---- Long-lived abuild signing key (host) -> (container) ----
ABUILD_CONT_DIR="/home/builder/.abuild"
ABUILD_KEY_DIR="${ABUILD_KEY_DIR:-$REPO_DIR/private/abuildkeys}"
ABUILD_KEY_NAME="${ABUILD_KEY_NAME:-build-000001}"

ABUILD_PRIV="$ABUILD_KEY_DIR/${ABUILD_KEY_NAME}.rsa"
ABUILD_PUB="$ABUILD_KEY_DIR/${ABUILD_KEY_NAME}.rsa.pub"

mkdir -p "$OUT_DIR"
mkdir -p "$ABUILD_KEY_DIR"

# Guardrails: fail early if key material isn't present.
[ -f "$ABUILD_PRIV" ] || { echo "ERROR: missing $ABUILD_PRIV (run: make abuild-key)"; exit 1; }
[ -f "$ABUILD_PUB"  ] || { echo "ERROR: missing $ABUILD_PUB (run: make abuild-key)"; exit 1; }

docker build \
  -t "alpine-ec2-tpm-builder:${ALPINE_VER}" \
  --build-arg "ALPINE_VER=${ALPINE_VER}" \
  -f "$SCRIPT_DIR/Dockerfile" \
  "$SCRIPT_DIR"

# Decide whether to allocate a TTY
if [ -t 0 ] && [ -t 1 ]; then
  DOCKER_TTY="-it"
else
  DOCKER_TTY=""
fi

# Run the build. We bind-mount the repo-root abuild key dir so signing is stable.
docker run --rm ${DOCKER_TTY} \
  -u builder \
  -e ABUILD_KEY_NAME="$ABUILD_KEY_NAME" \
  -v "$SCRIPT_DIR":/host:ro \
  -v "$OUT_DIR":/out \
  -v "$ABUILD_PRIV:$ABUILD_CONT_DIR/${ABUILD_KEY_NAME}.rsa:ro" \
  -v "$ABUILD_PUB:$ABUILD_CONT_DIR/${ABUILD_KEY_NAME}.rsa.pub:ro" \
  -v "$ABUILD_PUB:/etc/apk/keys/build_key.rsa.pub:ro" \
  -v alpine-ec2-tpm-ccache:/home/builder/.cache/ccache \
  "alpine-ec2-tpm-builder:${ALPINE_VER}" \
  /bin/sh /host/container-build.sh

# ---- write build manifest for reproducibility/debugging ----

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
  echo "build_id=$BUILD_ID"
  echo "git_head=$GIT_HEAD"
} > "$MANIFEST"

grep -q '^modules_release=.' "$MANIFEST" || {
  echo "ERROR: modules_release missing" >&2
  cat "$MANIFEST" >&2
  exit 1
}

echo "Wrote: $MANIFEST"
