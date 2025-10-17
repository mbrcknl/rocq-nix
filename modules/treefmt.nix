{
  config,
  lib,
  inputs,
  rocq-nix-lib,
  treefmt-nix,
  ...
}:

let
  inherit (lib) types;
  inherit (rocq-nix-lib) submoduleType;

  treefmtConfigModule = {
    freeformType = types.attrsOf types.anything;
  };

  treefmts = lib.genAttrs config.systems (
    system:
    let
      pkgs = config.nixpkgs.pkgs.${system};
      treefmtEval = treefmt-nix.lib.evalModule pkgs config.treefmt;
    in
    treefmtEval.config.build
  );

  mapTreefmts = f: lib.mapAttrs (_: f) treefmts;

  formatter = mapTreefmts (treefmt: treefmt.wrapper);
  checks = mapTreefmts (treefmt: {
    formatting = treefmt.check inputs.self;
  });
in

{
  options.treefmt = lib.mkOption {
    type = types.nullOr (submoduleType treefmtConfigModule);
    default = null;
  };

  config.flake.formatter = lib.mkIf (config.treefmt != null) formatter;
  config.flake.checks = lib.mkIf (config.treefmt != null) checks;
}
