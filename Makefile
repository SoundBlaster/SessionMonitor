# Native CLI + macOS app quality gates. Project is generated from project.yml.
SHELL := /bin/sh

SWIFT ?= xcrun swift
XCODEBUILD ?= xcodebuild
# The pinned SpecificationCore/Kit macro implementations are trusted for these builds.
# Matches XcodeBuildMCP's per-build behavior; does not alter global Xcode settings.
XCODEBUILD_FLAGS ?= -skipMacroValidation
XCODEGEN ?= xcodegen
XCODEBUILDMCP ?= xcodebuildmcp
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

.PHONY: help doctor generate guard-package guard-app lint-version resolve build-cli test-core build-mcp
.PHONY: lint-core lint lint-architecture build-macos test-macos check-core check archive

help:
	@printf '%s\n' 'doctor resolve build-cli test-core lint-core check-core' 'generate build-macos build-mcp test-macos lint lint-architecture check archive'

generate:
	@test -f Apps/MonitorMac/Local.xcconfig || printf '%s\n' '// Local signing overrides (not committed).' 'CODE_SIGN_IDENTITY = -' > Apps/MonitorMac/Local.xcconfig
	$(XCODEGEN) generate --spec Apps/MonitorMac/project.yml
	@mkdir -p "$(PROJECT)/project.xcworkspace/xcshareddata/swiftpm"
	cp Apps/MonitorMac/Package.resolved "$(PROJECT)/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

doctor:
	$(SWIFT) --version
	$(XCODEBUILD) -version
	$(SWIFTLINT) version

guard-package:
	@test -f Package.swift || { echo 'Package.swift is required in the current directory.' >&2; exit 2; }

guard-app: generate
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
	$(XCODEBUILD) $(XCODEBUILD_FLAGS) -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" $(SIGNING_ARGS) build

build-mcp: guard-app
	$(XCODEBUILDMCP) macos build --project-path "$(PROJECT)" --scheme "$(SCHEME)" --derived-data-path "$(DERIVED_DATA)" --prefer-xcodebuild

test-macos: guard-app
	@mkdir -p "$(BUILD_ROOT)"
	$(XCODEBUILD) $(XCODEBUILD_FLAGS) -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -resultBundlePath "$(RESULT_BUNDLE)" $(SIGNING_ARGS) test

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
	$(XCODEBUILD) $(XCODEBUILD_FLAGS) -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$(DERIVED_DATA)" -archivePath "$(ARCHIVE_PATH)" $(SIGNING_ARGS) archive
