{
  flakeRoot,
}:

let
  system = builtins.currentSystem;
  flake = builtins.getFlake flakeRoot;

  pkgs = flake.lib.nixpkgs.pkgs.${system};
  inherit (pkgs) lib;

  inherit (lib)
    filterAttrs
    importJSON
    hasAttr
    pathExists
    ;

  currentSetupPath = flakeRoot + "/.rocq-nix/current/setup.json";
  currentSetup = if pathExists currentSetupPath then { } else importJSON currentSetupPath;

  defaultRocq.rocq = lib.head flake.lib.rocq.versions;
  defaultSetup = filterAttrs (n: _: hasAttr n nullSetup) currentSetup;

  nullSetup = {
    rocq = null;
    vsrocq = null;
    emacs = false;
    envrc = false;
    mise = false;
  };
in

{
  mkSetupDerivation =
    {
      setupArgs,
    }:
    let
      newSetup = defaultSetup // setupArgs;
      completeSetup = nullSetup // defaultRocq // newSetup;

    in
    null;
}
