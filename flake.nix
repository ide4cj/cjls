{
  description = "Cangjie language server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    cangjie-nix = {
      url = "github:ide4cj/cangjie-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, cangjie-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system} = rec {
        cjls = pkgs.callPackage ./nix/package.nix {
          cangjie = cangjie-nix.packages.${system}.nightly;
        };
        default = cjls;
      };
    };
}
