LOCAL_UID := $(shell id -u)
LOCAL_GID := $(shell id -g)
USER ?= $(shell id -un)
BUILD_ID := $(shell git describe --tags --always --dirty 2>/dev/null || echo unknown)
GIT_HEAD := $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
OUT_ROOT ?= ./private/uki-build-$(BUILD_ID)

COMPOSE_RUN := LOCAL_UID=$(LOCAL_UID) LOCAL_GID=$(LOCAL_GID) BUILD_ID=$(BUILD_ID) GIT_HEAD=$(GIT_HEAD) OUT_ROOT=$(OUT_ROOT) docker compose run --rm
SBVERIFY_CMD := sbverify --cert /tmp/db.crt /uki/BOOTAA64.EFI && echo "OK: signature verifies"

ABUILD_KEY_SCRIPT := ./scripts/init-abuild-key.sh
ABUILD_KEY_DIR := ./private/abuildkeys
ABUILD_KEY_NAME ?= build-000001
ABUILD_KEY_DIR  := ./private/abuildkeys
ABUILD_KEY_PRIV := $(ABUILD_KEY_DIR)/$(ABUILD_KEY_NAME).rsa
ABUILD_KEY_PUB  := $(ABUILD_KEY_DIR)/$(ABUILD_KEY_NAME).rsa.pub
ABUILD_KEY_CONF := $(ABUILD_KEY_DIR)/abuild.conf

.PHONY: build clean prepare-target uki-build verify tpm-build show-uki-id abuild-key

build:
	mkdir -p $(OUT_ROOT)/kernel $(OUT_ROOT)/target-root $(OUT_ROOT)/uki
	$(MAKE) tpm-build
	$(MAKE) prepare-target
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

# Ensure the long-lived abuild signing key exists before building packages.
abuild-key: $(ABUILD_KEY_PRIV) $(ABUILD_KEY_PUB) $(ABUILD_KEY_CONF)

$(ABUILD_KEY_PRIV) $(ABUILD_KEY_PUB) $(ABUILD_KEY_CONF): $(ABUILD_KEY_SCRIPT)
	@$(ABUILD_KEY_SCRIPT)

tpm-build: abuild-key
	OUT_DIR=$(OUT_ROOT)/kernel ABUILD_KEY_NAME=$(ABUILD_KEY_NAME) ./tpm/build.sh

verify:
	$(COMPOSE_RUN) --entrypoint /bin/sh uki-build -lc '$(SBVERIFY_CMD)'
