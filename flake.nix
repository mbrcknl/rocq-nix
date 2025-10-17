{
  description = "Tools for working with Rocq Prover projects";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    rocq-nix-config.url = "github:mbrcknl/rocq-nix-config";
    rocq-nix-config.flake = false;

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      treefmt-nix,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      inherit (rocq-nix-config) systems;

      rocq-nix-config = import inputs.rocq-nix-config {
        inherit lib rocq-nix-lib;
      };

      rocq-nix-lib = import lib/lib.nix {
        inherit
          lib
          nixpkgs
          rocq-nix-config
          rocq-nix-lib
          treefmt-nix
          ;
      };

      treefmt = {
        programs.black.enable = true;
        programs.nixfmt.enable = true;
      };

      treefmts = lib.genAttrs systems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          treefmtEval = treefmt-nix.lib.evalModule pkgs treefmt;
        in
        treefmtEval.config.build
      );
    in
    {
      checks = lib.genAttrs systems (system: {
        formatting = treefmts.${system}.check self;
      });

      formatter = lib.mapAttrs (_: treefmt: treefmt.wrapper) treefmts;

      lib = rocq-nix-lib;
    };
}
