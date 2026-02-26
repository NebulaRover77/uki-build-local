# syntax=docker/dockerfile:1
FROM alpine:3.23

# Tools needed by uki-build.sh:
# - objdump/objcopy: binutils
# - sbsign/sbverify: sbsigntool
# - install: coreutils (busybox has install on alpine, but coreutils is safer)
# - file: file
# - awk: busybox provides awk; keep gawk optional
RUN apk add --no-cache \
    binutils \
    sbsigntool \
    file \
    coreutils \
    ca-certificates

WORKDIR /work

# Copy your script into the image
COPY uki-build.sh /usr/local/bin/uki-build.sh
RUN chmod +x /usr/local/bin/uki-build.sh

# Default mount points / expected paths
# You will typically mount:
#  - /mnt/target (rootfs that contains /etc/os-release, /boot/vmlinuz-*, /boot/initramfs-*, etc.)
#  - /tmp inputs (db.key, db.crt, stub) OR pass different paths as args
VOLUME ["/mnt/target"]

ENTRYPOINT ["/usr/local/bin/uki-build.sh"]
CMD ["/mnt/target", "/tmp/db.key", "/tmp/db.crt", "/tmp/linuxaa64.efi.stub"]
