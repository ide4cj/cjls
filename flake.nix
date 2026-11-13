{
  description = "Cangjie language server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
    cangjie-nix.url = "github:ide4cj/cangjie-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      cangjie-nix,
      ...
    }:
    # TODO(https://github.com/ide4cj/cangjie-nix/issues/6): support macos
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        sdk = cangjie-nix.packages.${system};
        sdk-version = pkgs.lib.removeSuffix "\n" (builtins.readFile ./.cangjie-version);
        cangjie = sdk.nightly."${sdk-version}".override {
          inherit (pkgs) stdenv;
          stdx = null;
        };
        stdx = sdk.stdx.nightly."${sdk-version}".static;
      in
      {
        packages = rec {
          cjls = pkgs.callPackage ./nix/package.nix { inherit cangjie stdx; };
          default = cjls;
        };

        devShells = {
          default = pkgs.mkShell {
            packages = [ cangjie ];

            CANGJIE_HOME = "${cangjie}";
            CANGJIE_STDX_PATH = "${stdx}/stdx";

            shellHook = ''
              echo "~~ in cangjie environment ~~"
              echo "$(cjc --version)"
            '';
          };
        };
      }
    );
}
