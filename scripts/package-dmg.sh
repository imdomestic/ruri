#!/bin/zsh
# 使用方式：RURI_VERSION=0.10.6 RURI_BUILD_NUMBER=22 scripts/package-dmg.sh
# RURI_MICROSOFT_CLIENT_ID 可以覆盖公开的应用标识。
set -euo pipefail
cd "${0:A:h:h}"
export TMPDIR="$(pwd)/.work/tmp"
export RURI_BUILD_DIR="${RURI_BUILD_DIR:-$(pwd)/.work/release}"
export RURI_ARCH="${RURI_ARCH:-universal}"
# 发布固定使用唯一应用路径，凭据配置明确保持为空。
if [[ -n "${RURI_APP_PATH:-}" && "$RURI_APP_PATH" != 'build/Ruri Chorus.app' ]]; then
  print -u2 -- 'Release packaging requires RURI_APP_PATH=build/Ruri Chorus.app.'
  exit 2
fi
export RURI_APP_PATH='build/Ruri Chorus.app'
export RURI_CURSEFORGE_API_KEY=''
case "$RURI_ARCH" in
  universal) required_architectures=(arm64 x86_64) ;;
  arm64|x86_64) required_architectures=("$RURI_ARCH") ;;
  *) print -u2 -- "Unsupported RURI_ARCH: $RURI_ARCH."; exit 2 ;;
esac
mkdir -p "$TMPDIR" "$RURI_BUILD_DIR"
scripts/build-app.sh release --build-system swiftbuild "$@"

app="$(pwd)/$RURI_APP_PATH"
version="$(plutil -extract RuriVersion raw -o - "$app/Contents/Info.plist")"
architecture="$RURI_ARCH"
for binary in "$app/Contents/MacOS/Ruri" "$app/Contents/Helpers/ruri-cli" "$app/Contents/Helpers/ruri-monitor"; do
  lipo "$binary" -verify_arch "${required_architectures[@]}"
done
for host_architecture in arm64 x86_64; do
  lipo "$app/Contents/Helpers/RuriGame.app/Contents/MacOS/ruri-game" -verify_arch "$host_architecture"
  lipo "$app/Contents/Helpers/RuriGame.app/Contents/Frameworks/libRuriGameSupport.dylib" -verify_arch "$host_architecture"
done

mkdir -p build/dmg
stage_dir="$(mktemp -d "$(pwd)/build/.ruri-dmg.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
mkdir "$stage_dir/volume"
ditto "$app" "$stage_dir/volume/Ruri Chorus.app"
ln -s /Applications "$stage_dir/volume/Applications"
cp LICENSE "$stage_dir/volume/LICENSE"
filename="Ruri-Chorus-$version-macOS-$architecture.dmg"
hdiutil create -volname "Ruri Chorus $version" -srcfolder "$stage_dir/volume" \
  -format UDZO -fs HFS+ "$stage_dir/$filename"
hdiutil verify "$stage_dir/$filename"
mv -f "$stage_dir/$filename" "build/dmg/$filename"
(
  cd build/dmg
  shasum -a 256 "$filename" > "$filename.sha256"
)
print -- "Packaged $(pwd)/build/dmg/$filename"
