# Copy into the application repository with .swiftlint.yml and .fsd-ios.yml.
# Project/product defaults follow the architecture draft and are overridable.
SHELL := /bin/sh

SWIFT ?= xcrun swift
XCODEBUILD ?= xcodebuild
SWIFTLINT ?= swiftlint
SWIFTLINT_VERSION ?= 0.63.3
FSD ?= fsd-ios
CLI_PRODUCT ?= codex-monitor
PROJECT ?= Apps/MonitorMac/MonitorMac.xcodeproj
SCHEME ?= MonitorMac
CONFIGURATION ?= Debug
DESTINATION ?= platform=macOS
BUILD_ROOT ?= .build/quality
DERIVED_DATA ?= .build/xcode
RUN_ID := $(shell date -u +%Y%m%dT%H%M%S)-$(shell uuidgen)
RESULT_BUNDLE ?= $(BUILD_ROOT)/$(RUN_ID).xcresult
ARCHIVE_PATH ?= $(BUILD_ROOT)/MonitorMac-$(RUN_ID).xcarchive
DEVELOPMENT_TEAM ?=
ALLOW_PROVISIONING_UPDATES ?= NO

SIGNING_ARGS := CODE_SIGN_STYLE=Automatic
ifneq ($(strip $(DEVELOPMENT_TEAM)),)
SIGNING_ARGS += DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)"
endif
ifeq ($(ALLOW_PROVISIONING_UPDATES),YES)
SIGNING_ARGS += -allowProvisioningUpdates
endif

.PHONY: help doctor guard-package guard-app lint-version resolve build-cli test-core
.PHONY: lint-core lint lint-architecture build-macos test-macos check-core check archive

help:
	@printf '%s\n' 'doctor resolve build-cli test-core lint-core check-core' 'build-macos test-macos lint lint-architecture check archive' 'Override PROJECT, SCHEME, CLI_PRODUCT and DEVELOPMENT_TEAM for the actual project.'

doctor:
	$(SWIFT) --version
	$(XCODEBUILD) -version
	$(SWIFTLINT) version

guard-package:
	@test -f Package.swift || { echo 'Package.swift is required in the current directory.' >&2; exit 2; }

guard-app:
	@test -d "$(PROJECT)" || { echo 'Set PROJECT to the macOS .xcodeproj and SCHEME to its shared scheme.' >&2; exit 2; }

lint-version:
	@test "$$($(SWIFTLINT) version)" = "$(SWIFTLINT_VERSION)" || { echo 'SwiftLint version differs from the project pin.' >&2; exit 2; }

resolve: guard-package
	$(SWIFT) package resolve

build-cli: guard-package
	$(SWIFT) build --configuration debug --product "$(CLI_PRODUCT)"

test-core: guard-package
	$(SWIFT) test

lint-core: lint-version
	$(SWIFTLINT) lint --strict --force-exclude --config .swiftlint.yml Sources Tests

lint: lint-version
	$(SWIFTLINT) lint --strict --force-exclude --config .swiftlint.yml Sources Tests Apps

lint-architecture:
	$(FSD) lint --config .fsd-ios.yml --strict --architecture

build-macos: guard-app
	$(XCODEBUILD) -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" $(SIGNING_ARGS) build

test-macos: guard-app
	@mkdir -p "$(BUILD_ROOT)"
	$(XCODEBUILD) -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -resultBundlePath "$(RESULT_BUNDLE)" $(SIGNING_ARGS) test

# Explicit ordering also holds under make -j. No automatic source correction.
check-core:
	$(MAKE) build-cli
	$(MAKE) lint-core
	$(MAKE) test-core

check:
	$(MAKE) build-cli
	$(MAKE) build-macos
	$(MAKE) lint
	$(MAKE) lint-architecture
	$(MAKE) test-core
	$(MAKE) test-macos

# Local archive only. Export, notarization and publication are separate workflows.
archive: guard-app
	@mkdir -p "$(BUILD_ROOT)"
	$(XCODEBUILD) -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$(DERIVED_DATA)" -archivePath "$(ARCHIVE_PATH)" $(SIGNING_ARGS) archive
