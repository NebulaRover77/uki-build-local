LOCAL_UID := $(shell id -u)
LOCAL_GID := $(shell id -g)
USER ?= $(shell id -un)
BUILD_ID_RAW := $(shell git describe --tags --always --dirty 2>/dev/null || echo unknown)
BUILD_ID := $(shell printf '%s' '$(BUILD_ID_RAW)' | tr -c 'A-Za-z0-9._+-' '_' )
GIT_HEAD := $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
OUT_ROOT ?= $(HOME)/tmp/uki-build-$(USER)-$(BUILD_ID)

COMPOSE_RUN := LOCAL_UID=$(LOCAL_UID) LOCAL_GID=$(LOCAL_GID) BUILD_ID=$(BUILD_ID) GIT_HEAD=$(GIT_HEAD) OUT_ROOT=$(OUT_ROOT) docker compose run --rm
SBVERIFY_CMD := sbverify --cert $$HOME/tmp/db.crt /uki/BOOTAA64.EFI && echo "OK: signature verifies"

.PHONY: build clean prepare-target uki-build verify tpm-build show-uki-id

build:
	mkdir -p $(OUT_ROOT)/kernel $(OUT_ROOT)/target-root $(OUT_ROOT)/uki
	$(MAKE) tpm-build
	$(MAKE) prepare-target
	$(MAKE) verify
	$(MAKE) uki-build
	$(MAKE) verify

clean:
	rm -rf $(OUT_ROOT)/uki/*
	rm -rf $(OUT_ROOT)/target-root/*
	rm -f $(OUT_ROOT)/kernel/*.sync-conflict*

show-uki-id:
	@mkdir -p $(HOME)/tmp
	@objcopy -O binary --only-section=.osrel $(OUT_ROOT)/uki/BOOTAA64.EFI $(HOME)/tmp/osrel.$$ && \
	strings $(HOME)/tmp/osrel.$$ | egrep '^(IMAGE_VERSION|GIT_HEAD)=' && \
	rm -f $(HOME)/tmp/osrel.$$

prepare-target:
	$(COMPOSE_RUN) prepare-target

uki-build:
	$(COMPOSE_RUN) uki-build

tpm-build:
	OUT_DIR=$(OUT_ROOT)/kernel ./tpm/build.sh

verify:
	$(COMPOSE_RUN) --entrypoint /bin/sh uki-build -lc '$(SBVERIFY_CMD)'
