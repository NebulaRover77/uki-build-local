#!/bin/sh
set -euo pipefail

TARGET_ROOT="${1:-/mnt/target}"
DB_KEY="${2:-/tmp/db.key}"
DB_CRT="${3:-/tmp/db.crt}"
STUB="${4:-/tmp/linuxaa64.efi.stub}"

CMDLINE_FILE=/tmp/cmdline
OSREL_FILE=/tmp/os-release.uki
UNSIGNED=/tmp/BOOTAA64.EFI.unsigned
SIGNED=/tmp/BOOTAA64.EFI

OSREL="${TARGET_ROOT}/etc/os-release"
VMLINUX="${TARGET_ROOT}/boot/vmlinuz-tpm-ec2"
INITRD="${TARGET_ROOT}/boot/initramfs-tpm-ec2"
DEST_DIR="${DEST_DIR:-/uki}"
DEST_EFI="${DEST_DIR}/BOOTAA64.EFI"
BUILD_ID="${BUILD_ID:-unknown}"
GIT_HEAD="${GIT_HEAD:-unknown}"
SBKEYS_DIR="${SBKEYS_DIR:-/sbkeys}"

die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN:  $*" >&2; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

# Checks readability AND catches broken symlinks with a better message
need_path_r() {
  p="$1"
  if [ -L "$p" ] && [ ! -e "$p" ]; then
    warn "$p is a broken symlink:"
    ls -la "$p" >&2 || true
    ls -la "$(dirname "$p")" >&2 || true
    die "broken symlink: $p"
  fi
  [ -r "$p" ] || {
    warn "missing/unreadable: $p"
    ls -la "$(dirname "$p")" >&2 || true
    die "required file not readable: $p"
  }
}

if [ "${DEBUG:-0}" = "1" ]; then
  set -x
  echo "DEBUG: TARGET_ROOT=$TARGET_ROOT" >&2
  echo "DEBUG: DB_KEY=$DB_KEY" >&2
  echo "DEBUG: DB_CRT=$DB_CRT" >&2
  echo "DEBUG: STUB=$STUB" >&2
fi

# tool sanity
need_cmd objdump
need_cmd objcopy
need_cmd sbsign
need_cmd sbverify
need_cmd awk
need_cmd install
need_cmd file

# input sanity (prints the failing one)
need_path_r "$OSREL"
need_path_r "$VMLINUX"
need_path_r "$INITRD"
need_path_r "$DB_KEY"
need_path_r "$DB_CRT"
need_path_r "$STUB"

install -d "$DEST_DIR"

cp "$OSREL" "$OSREL_FILE"
printf '\nIMAGE_VERSION=%s\nGIT_HEAD=%s\n' "$BUILD_ID" "$GIT_HEAD" >> "$OSREL_FILE"

printf "%s\n" \
  "root=LABEL=ROOT ro modules=sd-mod,usb-storage,ext4,gpio_pl061,ena console=ttyS0,115200n8 earlycon loglevel=7 ignore_loglevel" \
  > "$CMDLINE_FILE"

OBJDUMP_OUT="$(objdump -p "$STUB" 2>/dev/null || true)"
IMAGE_BASE_HEX="$(printf '%s\n' "$OBJDUMP_OUT" | awk '/ImageBase/{print $2; exit}')"
[ -n "${IMAGE_BASE_HEX:-}" ] || die "could not parse ImageBase from stub: $STUB"
IMAGE_BASE_HEX="${IMAGE_BASE_HEX#0x}"
BASE=$((16#${IMAGE_BASE_HEX}))

vma() { printf '0x%x' "$((BASE + $1))"; }

objcopy \
  --add-section .osrel="$OSREL_FILE"     --change-section-vma .osrel="$(vma 0x20000)" \
  --add-section .cmdline="$CMDLINE_FILE" --change-section-vma .cmdline="$(vma 0x30000)" \
  --add-section .linux="$VMLINUX"        --change-section-vma .linux="$(vma 0x2000000)" \
  --add-section .initrd="$INITRD"        --change-section-vma .initrd="$(vma 0x3000000)" \
  "$STUB" "$UNSIGNED" || die "objcopy failed"

file "$UNSIGNED" || true
objdump -f "$UNSIGNED" || true

sbsign --key "$DB_KEY" --cert "$DB_CRT" --output "$SIGNED" "$UNSIGNED"
sbverify --cert "$DB_CRT" "$SIGNED"

install -m 0644 "$SIGNED" "$DEST_EFI"

PCR_TOOL="/opt/NitroTPM-Tools/target/release/nitro-tpm-pcr-compute"
PCR_JSON="${DEST_EFI}.pcr.json"
PCR4_FILE="${DEST_EFI}.pcr4"
SHA384_FILE="${DEST_EFI}.sha384"

if [ -x "$PCR_TOOL" ]; then
  echo "Computing Nitro PCR4 (SHA384)..."

  need_path_r "$SBKEYS_DIR/PK.esl"
  need_path_r "$SBKEYS_DIR/KEK.esl"
  need_path_r "$SBKEYS_DIR/db.esl"
  need_path_r "$SBKEYS_DIR/dbx.esl"

  "$PCR_TOOL" \
    --image "$DEST_EFI" \
    --PK "$SBKEYS_DIR/PK.esl" \
    --KEK "$SBKEYS_DIR/KEK.esl" \
    --db "$SBKEYS_DIR/db.esl" \
    --dbx "$SBKEYS_DIR/dbx.esl" \
    > "$PCR_JSON"

  # Extract PCR4 value from JSON
  PCR4="$(awk -F'"' '/"PCR4"/{print $4}' "$PCR_JSON")"
  echo "$PCR4" > "$PCR4_FILE"

  # Also save raw file SHA384
  sha384sum "$DEST_EFI" | awk '{print $1}' > "$SHA384_FILE"

  echo "Saved:"
  echo "  $PCR_JSON"
  echo "  $PCR4_FILE"
  echo "  $SHA384_FILE"
else
  echo "WARN: nitro-tpm-pcr-compute not found; skipping PCR calculation"
fi

rm -f "$CMDLINE_FILE" "$OSREL_FILE" "$UNSIGNED" "$SIGNED"
echo "OK: wrote signed UKI to $DEST_EFI"
