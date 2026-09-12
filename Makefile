# Native CLI + macOS app quality gates. Project is generated from project.yml.
SHELL := /bin/sh

SWIFT ?= xcrun swift
SWIFT_FLAGS ?=
XCODEBUILD ?= xcodebuild
# The pinned SpecificationCore/Kit macro implementations are trusted for these builds.
# Matches XcodeBuildMCP's per-build behavior; does not alter global Xcode settings.
XCODEBUILD_FLAGS ?= -skipMacroValidation
XCODEGEN ?= xcodegen
XCODEBUILDMCP ?= xcodebuildmcp
SWIFTLINT ?= swiftlint
SWIFTLINT_VERSION ?= 0.63.3
FSD ?= fsd-ios
ACTIONLINT ?= actionlint
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
.PHONY: ci lint-ci test-architecture test-cli

help:
	@printf '%s\n' 'doctor resolve build-cli test-core test-cli lint-core check-core' 'generate build-macos build-mcp test-macos lint lint-architecture check archive' 'ci lint-ci test-architecture'

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
	$(SWIFT) build $(SWIFT_FLAGS) --configuration debug --product "$(CLI_PRODUCT)"

test-core: guard-package
	$(SWIFT) test $(SWIFT_FLAGS)

# check/check-core build the executable first; this harness exercises real process signals.
test-cli: guard-package
	python3 scripts/tests/watch-cli-smoke.py --binary "$$($(SWIFT) build $(SWIFT_FLAGS) --configuration debug --show-bin-path)/$(CLI_PRODUCT)"
	python3 scripts/tests/snapshot-cli-smoke.py --binary "$$($(SWIFT) build $(SWIFT_FLAGS) --configuration debug --show-bin-path)/$(CLI_PRODUCT)"

lint-core: lint-version
	$(SWIFTLINT) lint --strict --force-exclude --config .swiftlint.yml Sources Tests

lint: lint-version
	$(SWIFTLINT) lint --strict --force-exclude --config .swiftlint.yml Sources Tests Apps

lint-architecture:
	$(FSD) lint --config .fsd-ios.yml --strict --architecture

test-architecture:
	FSD="$(FSD)" bash scripts/ci/check-fsd-boundary.sh

lint-ci:
	$(ACTIONLINT) -color
	bash -n scripts/ci/install-tools.sh scripts/ci/check-fsd-boundary.sh

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
	$(MAKE) test-cli

check:
	$(MAKE) build-cli
	$(MAKE) build-macos
	$(MAKE) lint
	$(MAKE) lint-architecture
	$(MAKE) test-architecture
	$(MAKE) test-core
	$(MAKE) test-cli
	$(MAKE) test-macos

# Same native gates as local check; ad-hoc signing needs no Developer credentials.
# Explicit flags override Local.xcconfig without changing the developer's file.
ci:
	$(MAKE) check SWIFT_FLAGS="--force-resolved-versions" \
		XCODEBUILD_FLAGS="$(XCODEBUILD_FLAGS) -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution" \
		SIGNING_ARGS="CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="
	git diff --exit-code -- Package.resolved Apps/MonitorMac/Package.resolved

# Local archive only. Export, notarization and publication are separate workflows.
archive: guard-app
	@mkdir -p "$(BUILD_ROOT)"
	$(XCODEBUILD) $(XCODEBUILD_FLAGS) -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$(DERIVED_DATA)" -archivePath "$(ARCHIVE_PATH)" $(SIGNING_ARGS) archive
