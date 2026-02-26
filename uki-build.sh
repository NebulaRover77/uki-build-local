#!/bin/sh
set -euo pipefail

TARGET_ROOT="${1:-/mnt/target}"
DB_KEY="${2:-/tmp/db.key}"
DB_CRT="${3:-/tmp/db.crt}"
STUB="${4:-/tmp/linuxaa64.efi.stub}"

CMDLINE_FILE=/tmp/cmdline
UNSIGNED=/tmp/BOOTAA64.EFI.unsigned
SIGNED=/tmp/BOOTAA64.EFI

OSREL="${TARGET_ROOT}/etc/os-release"
VMLINUX="${TARGET_ROOT}/boot/vmlinuz-tpm-ec2"
INITRD="${TARGET_ROOT}/boot/initramfs-tpm-ec2"
DEST_DIR="${TARGET_ROOT}/boot/efi/EFI/BOOT"
DEST_EFI="${DEST_DIR}/BOOTAA64.EFI"

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
  --add-section .osrel="$OSREL"          --change-section-vma .osrel="$(vma 0x20000)" \
  --add-section .cmdline="$CMDLINE_FILE" --change-section-vma .cmdline="$(vma 0x30000)" \
  --add-section .linux="$VMLINUX"        --change-section-vma .linux="$(vma 0x2000000)" \
  --add-section .initrd="$INITRD"        --change-section-vma .initrd="$(vma 0x3000000)" \
  "$STUB" "$UNSIGNED" || die "objcopy failed"

file "$UNSIGNED" || true
objdump -f "$UNSIGNED" || true

sbsign --key "$DB_KEY" --cert "$DB_CRT" --output "$SIGNED" "$UNSIGNED"
sbverify --cert "$DB_CRT" "$SIGNED"

install -m 0644 "$SIGNED" "$DEST_EFI"

rm -f "$CMDLINE_FILE" "$UNSIGNED" "$SIGNED"
echo "OK: wrote signed UKI to $DEST_EFI"
