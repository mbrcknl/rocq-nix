{
  description = "Tools for working with Rocq Prover projects";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    rocq-nix-config.url = "github:mbrcknl/rocq-nix-config";
    rocq-nix-config.flake = false;
  };

  outputs = { nixpkgs, rocq-nix-config, ... }:
    let
      inherit (nixpkgs) lib;
      inherit (lib) flip genAttrs importJSON;

      importConfig = name: importJSON (rocq-nix-config + "/${name}.json");

      config = flip genAttrs importConfig [
        "systems"
        "vsrocq"
      ];

      mkSystem = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          mk_vsrocq = version: pkgs.fetchFromGitHub {
            owner = "rocq-prover";
            repo = "vsrocq";
            inherit (version) hash tag;
          };

          vsrocq = mk_vsrocq config.vsrocq.versions.${config.vsrocq.default};
        in
        {
          inherit vsrocq;
        };

      packages = genAttrs config.systems mkSystem;

    in
    {
      lib = { inherit config packages; };
    };
}
