LOCAL_UID := $(shell id -u)
LOCAL_GID := $(shell id -g)

COMPOSE_RUN := LOCAL_UID=$(LOCAL_UID) LOCAL_GID=$(LOCAL_GID) docker compose run --rm
SBVERIFY_CMD := sbverify --cert /tmp/db.crt /mnt/target/boot/efi/EFI/BOOT/BOOTAA64.EFI && echo "OK: signature verifies"

.PHONY: build prepare-target uki-build verify tpm-build

build:
	$(MAKE) prepare-target
	$(MAKE) uki-build
	$(MAKE) verify
	$(MAKE) tpm-build
	$(MAKE) verify

prepare-target:
	$(COMPOSE_RUN) prepare-target

uki-build:
	$(COMPOSE_RUN) uki-build

tpm-build:
	./tpm/build.sh

verify:
	$(COMPOSE_RUN) --entrypoint /bin/sh uki-build -lc '$(SBVERIFY_CMD)'
