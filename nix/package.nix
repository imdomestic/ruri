{
  lib,
  stdenv,
  swift,
  swiftpm,
  fetchSwiftPMDeps,
  apple-sdk_26,
  darwinMinVersionHook,
  jq,
  python3,
  rcodesign,
  sqlite,
  zlib,
  enableVex ? true,
}:
let
  infoPlist = builtins.readFile ../Resources/Info.plist;
  filterPins = ''
    jq 'del(.pins[] | select(.identity == "sparkle"${lib.optionalString (!enableVex) '' or .identity == "eventsource"''}))' Package.resolved > Package.resolved.new
    mv Package.resolved.new Package.resolved
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "ruri-launcher";
  version = lib.head (builtins.match ".*<key>RuriVersion</key><string>([^<]+)</string>.*" infoPlist);
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [ ../Package.swift ../Package.resolved ../Resources ../Sources ../Tests ../scripts ./icons ];
  };
  postPatch = filterPins;
  swiftpmDeps = fetchSwiftPMDeps {
    inherit (finalAttrs) pname version src;
    postPatch = filterPins;
    hash = if enableVex then "sha256-QaU+NDzoIeXU1Enxu8G3wmYhKnzDPD6hUJRh5K5J7x8=" else "sha256-HO5faDGc+dXwJ8vuFdxBZWxMOmNm0TMSyqDUblKDL2o=";
  };
  strictDeps = true;
  nativeBuildInputs = [ swift swiftpm jq python3 rcodesign ];
  buildInputs = [ apple-sdk_26 (darwinMinVersionHook "14.0") sqlite zlib ];
  env = {
    RURI_DISABLE_SPARKLE = "1";
    RURI_ENABLE_VEX = if enableVex then "1" else "0";
    RURI_CURSEFORGE_API_KEY = "";
  };
  postBuild = ''
    mkdir -p build/game-host
    hostFlags=(-mmacosx-version-min=14.0 -arch arm64 -arch x86_64 -fobjc-arc -O2 -Wall -Wextra -Werror)
    $CC "''${hostFlags[@]}" -dynamiclib -framework Foundation Sources/RuriGameHost/WorkingDirectory.m \
      -install_name @rpath/libRuriGameSupport.dylib -o build/game-host/libRuriGameSupport.dylib
    $CC "''${hostFlags[@]}" -framework AppKit -framework ImageIO \
      Sources/RuriGameHost/main.m Sources/RuriGameHost/HostProtocol.m Sources/RuriGameHost/GameApplication.m \
      -Lbuild/game-host -lRuriGameSupport -Wl,-rpath,@executable_path/../Frameworks -o build/game-host/ruri-game
  '';
  installPhase = ''
    runHook preInstall
    binPath="$(swiftpmBinPath)"
    app="$out/Applications/Ruri.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
    cp Resources/Info.plist "$app/Contents/Info.plist"
    cp Resources/ThirdPartyNotices.txt nix/icons/AppIcon/* "$app/Contents/Resources/"
    python3 scripts/lib/app.py bundle "$app"
    install -m755 "$binPath/Ruri" "$app/Contents/MacOS/Ruri"
    install -m755 "$binPath/ruri-cli" "$binPath/ruri-monitor" "$app/Contents/Helpers/"
    $STRIP "$app/Contents/MacOS/Ruri" "$app/Contents/Helpers/ruri-cli" "$app/Contents/Helpers/ruri-monitor"
    cp -R "$binPath"/*.bundle "$app/Contents/Resources/"
    python3 scripts/localization.py --compile "$app/Contents/Resources/Ruri_RuriLocalization.bundle"
    ${lib.optionalString enableVex ''python3 scripts/localization.py --compile "$app/Contents/Resources/Ruri_RuriVex.bundle"''}
    host="$app/Contents/Helpers/RuriGame.app"
    install -Dm644 Resources/GameHost-Info.plist "$host/Contents/Info.plist"
    install -Dm755 build/game-host/ruri-game "$host/Contents/MacOS/ruri-game"
    install -Dm755 build/game-host/libRuriGameSupport.dylib "$host/Contents/Frameworks/libRuriGameSupport.dylib"
    install -Dm644 -t "$host/Contents/Resources" nix/icons/GameHostIcon/*
    mkdir -p "$out/bin"
    ln -s "$app/Contents/Helpers/ruri-cli" "$out/bin/ruri"
    runHook postInstall
  '';
  postFixup = ''
    rcodesign sign --binary-identifier Contents/Helpers/ruri-cli:dev.ruri.launcher "$out/Applications/Ruri.app"
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/ruri" --version)" = "${finalAttrs.version}"
    "$out/bin/ruri" --help > /dev/null
    python3 scripts/localization.py --bundle "$out/Applications/Ruri.app"
    runHook postInstallCheck
  '';
  meta = {
    description = "Minecraft Java launcher for macOS";
    homepage = "https://github.com/guh0613/ruri";
    license = lib.licenses.gpl3Only;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "ruri";
  };
})
