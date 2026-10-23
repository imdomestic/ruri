#!/bin/zsh
# Build Ruri with the selected Xcode SDK and accurate Mach-O SDK metadata.
# Usage: scripts/swift-build.sh -c debug --product Ruri
# Tests: scripts/swift-build.sh test --filter AuthenticationTests
# DEVELOPER_DIR selects Xcode; RURI_BUILD_DIR optionally selects the build folder
# (release builds use its release-scratch subfolder). RURI_ARCH=x86_64 builds
# for Intel with the same Xcode; tests then run under Rosetta.
set -euo pipefail
cd "${0:A:h:h}"
source scripts/lib/build.sh
select_xcode

swift_command=build
if [[ "${1:-}" == test ]]; then
  swift_command=test
  shift
fi

configuration=debug
previous=
# This entry point builds this package for macOS. Keep SDK selection consistent
# between compilation and linking instead of allowing conflicting overrides.
for argument in "$@"; do
  case "$previous" in -c|--configuration) configuration="$argument" ;; esac
  previous="$argument"
  case "$argument" in
    --configuration=*) configuration="${argument#*=}" ;;
    --sdk|--sdk=*|--swift-sdk|--swift-sdk=*|--triple|--triple=*|--toolchain|--toolchain=*|--package-path|--package-path=*)
      print -u2 -- "Unsupported override: $argument. Use DEVELOPER_DIR to select the macOS toolchain/SDK."
      exit 2
      ;;
    --arch|--arch=*)
      print -u2 -- "Unsupported override: $argument. Use RURI_ARCH to select the target architecture."
      exit 2
      ;;
  esac
done

# 保留全部组件的锁定版本；切换组件时不改写 Package.resolved。
build_args=(--force-resolved-versions)
# Building every architecture with one compiler keeps an older toolchain's bugs
# out of a single slice. Each architecture builds in its own folder, because the
# products path does not name the architecture.
scratch_path="${RURI_BUILD_DIR:-.build}"
# 各组件组合使用独立产物目录，打包时只读取当前组合的资源。
if [[ "${RURI_ENABLE_VEX:-1}" == 0 ]]; then
  scratch_path="$scratch_path/without-vex"
else
  scratch_path="$scratch_path/with-vex"
fi
if [[ -n "${RURI_ARCH:-}" ]]; then
  case "$RURI_ARCH" in
    arm64|x86_64) ;;
    *) print -u2 -- "Unsupported RURI_ARCH: $RURI_ARCH. Use arm64 or x86_64."; exit 2 ;;
  esac
  build_args+=(--arch "$RURI_ARCH")
  scratch_path="$scratch_path/$RURI_ARCH"
fi
# A debug build in the same folder invalidates release intermediates, making the
# next release build recompile everything. Keep release in its own folder.
if [[ "$configuration" == release ]]; then scratch_path="$scratch_path/release-scratch"; fi
build_args+=(--scratch-path "$scratch_path")
# Querying a product path does not compile or validate application resources.
if [[ "$swift_command" == build ]] && (( ${@[(Ie)--show-bin-path]} )); then
  exec xcrun swift build "${build_args[@]}" "$@"
fi

python3 scripts/localization.py --check >&2
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
sdk_version="$(xcrun --sdk "$sdk_path" --show-sdk-version)"
package="$(xcrun swift package dump-package)"
platform="$(print -r -- "$package" | plutil -extract platforms.0.platformName raw -o - -)"
if [[ "$platform" != macos ]]; then
  print -u2 -- "Expected Package.swift to declare macOS as its first supported platform."
  exit 1
fi
deployment_target="$(print -r -- "$package" | plutil -extract platforms.0.version raw -o - -)"
# Keep SDK metadata consistent between compilation and linking.
build_args+=(--sdk "$sdk_path"
  -Xlinker -platform_version -Xlinker macos
  -Xlinker "$deployment_target" -Xlinker "$sdk_version")
if [[ "$swift_command" == test ]]; then
  host_app="$(pwd)/${RURI_BUILD_DIR:-.build}/game-host/RuriGame.app"
  if [[ "${RURI_BUILD_DIR:-}" == /* ]]; then host_app="$RURI_BUILD_DIR/game-host/RuriGame.app"; fi
  build_game_host "$host_app"
  export RURI_TEST_GAME_HOST="$host_app/Contents/MacOS/ruri-game"
  # Human-readable assertions use the source language on every CI host.
  # Localization tests scope their own contexts for other languages.
  export RURI_LANGUAGE="${RURI_LANGUAGE:-zh-Hans}"
fi
if [[ "$swift_command" == test && -n "${RURI_ARCH:-}" && "$RURI_ARCH" != "$(uname -m)" ]]; then
  # SwiftPM's test helpers only run natively. Build the bundles, then run each
  # one with the universal xctest agent under Rosetta.
  for argument in "$@"; do
    case "$argument" in
      --filter|--filter=*|--skip|--skip=*)
        print -u2 -- "Cross-architecture tests run the whole suite; $argument is unsupported."
        exit 2
        ;;
    esac
  done
  if (( ${@[(Ie)--no-parallel]} )); then export SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=1; fi
  build_flags=("${@:#--no-parallel}")
  xcrun swift build --build-tests "${build_args[@]}" "${build_flags[@]}"
  products="$(xcrun swift build "${build_args[@]}" "${build_flags[@]}" --show-bin-path)"
  failed=0
  for bundle in "$products"/*.xctest; do
    arch "-$RURI_ARCH" xcrun xctest "$bundle" || failed=1
  done
  exit $failed
fi
exec xcrun swift "$swift_command" "${build_args[@]}" "$@"
