LOCAL_UID := $(shell id -u)
LOCAL_GID := $(shell id -g)

.PHONY: build verify

build:
	LOCAL_UID=$(LOCAL_UID) LOCAL_GID=$(LOCAL_GID) docker compose run --rm prepare-target
	LOCAL_UID=$(LOCAL_UID) LOCAL_GID=$(LOCAL_GID) docker compose run --rm uki-build

verify:
	LOCAL_UID=$(LOCAL_UID) LOCAL_GID=$(LOCAL_GID) docker compose run --rm \
		--entrypoint /bin/sh uki-build -lc \
		'sbverify --cert /tmp/db.crt /mnt/target/boot/efi/EFI/BOOT/BOOTAA64.EFI && echo "OK: signature verifies"'
