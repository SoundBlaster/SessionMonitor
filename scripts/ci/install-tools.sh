#!/usr/bin/env bash
# Install official release archives into an isolated, disposable project directory.
set -euo pipefail

tool_root="$PWD/.build/ci-tools"
downloads="$tool_root/downloads"
mkdir -p "$downloads" "$tool_root/bin"

download() {
  local url="$1" digest="$2" destination="$3"
  curl --fail --location --silent --show-error --retry 3 --connect-timeout 20 \
    --max-time 180 "$url" --output "$destination"
  printf '%s  %s\n' "$digest" "$destination" | shasum --algorithm 256 --check
}

case "${1:-}" in
  native)
    test "$(uname -s)" = Darwin
    download https://github.com/realm/SwiftLint/releases/download/0.63.3/portable_swiftlint.zip \
      fb045e85e7cb3374f42a4840b6b85a0106302afa69035c0c6f29af4a44c810b6 "$downloads/swiftlint.zip"
    unzip -oq "$downloads/swiftlint.zip" -d "$tool_root/swiftlint"
    install -m 755 "$tool_root/swiftlint/swiftlint" "$tool_root/bin/swiftlint"

    download https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip \
      4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806 "$downloads/xcodegen.zip"
    unzip -oq "$downloads/xcodegen.zip" -d "$downloads/xcodegen"
    cp -R "$downloads/xcodegen/xcodegen/" "$tool_root/"

    download https://github.com/SoundBlaster/FSD/releases/download/v0.4.0/fsd-ios-0.4.0.tar.gz \
      c1cccb45bbf2cad5d336a639a4c63996aa79b2d33b67f3a7a5eb3b124b692823 "$downloads/fsd.tar.gz"
    tar -xzf "$downloads/fsd.tar.gz" -C "$tool_root" --strip-components=1

    "$tool_root/bin/swiftlint" version
    "$tool_root/bin/xcodegen" version
    "$tool_root/bin/fsd-ios" --version
    ;;
  workflow)
    case "$(uname -s)-$(uname -m)" in
      Linux-x86_64)
        platform=linux_amd64
        digest=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
        ;;
      Darwin-arm64)
        platform=darwin_arm64
        digest=aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f
        ;;
      *) echo 'Unsupported actionlint platform' >&2; exit 2 ;;
    esac
    download "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_${platform}.tar.gz" \
      "$digest" "$downloads/actionlint.tar.gz"
    tar -xzf "$downloads/actionlint.tar.gz" -C "$tool_root/bin" actionlint
    "$tool_root/bin/actionlint" --version
    ;;
  *) echo 'Usage: bash scripts/ci/install-tools.sh native|workflow' >&2; exit 2 ;;
esac
