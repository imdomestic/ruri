{
  description = "Ruri for macOS and its Xcode development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [ "aarch64-darwin" ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
      packageFor = system: (pkgsFor system).callPackage ./nix/package.nix { };
    in
    {
      packages = forEachSystem (system: {
        default = packageFor system;
        ruri-launcher = packageFor system;
        ruri-without-experiments = (packageFor system).override { enableVex = false; };
      });

      apps = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;
          ruri = packageFor system;
        in
        {
          default = {
            type = "app";
            program = "${pkgs.writeShellScript "ruri-open" ''
              exec /usr/bin/open -a "${ruri}/Applications/Ruri.app" "$@"
            ''}";
          };
          cli = {
            type = "app";
            program = "${ruri}/bin/ruri";
          };
        }
      );

      devShells = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          # Swift, SourceKit-LSP, the macOS SDK, actool and codesign come from
          # Xcode, as in CI and release builds, so the shell adds no compiler
          # or SDK of its own.
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.python3
              pkgs.nixfmt
            ];
            # Select Xcode for this shell without changing `xcode-select`, and
            # leave deployment targets to Package.swift as in CI.
            shellHook = ''
              unset MACOSX_DEPLOYMENT_TARGET
              if [ -z "''${DEVELOPER_DIR:-}" ]; then
                for xcode in /Applications/Xcode.app /Applications/Xcode-beta.app; do
                  if [ -d "$xcode/Contents/Developer" ]; then
                    export DEVELOPER_DIR="$xcode/Contents/Developer"
                    break
                  fi
                done
              fi
              if [ -n "''${DEVELOPER_DIR:-}" ]; then
                export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH"
              else
                echo "Install Xcode 27, or set DEVELOPER_DIR to its Contents/Developer directory."
              fi
            '';
          };
        }
      );

      checks = forEachSystem (system: {
        package = packageFor system;
        without-experiments = (packageFor system).override { enableVex = false; };
      });

      formatter = forEachSystem (system: (pkgsFor system).nixfmt-tree);
    };
}
