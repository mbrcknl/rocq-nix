{ lib, rocq-nix-lib, ... }:

let
  inherit (lib) types;
  inherit (rocq-nix-lib) submoduleOption submoduleType;

  rocqVersionType = submoduleType {
    options.compatible-rocq-version = lib.mkOption {
      type = types.str;
    };
    options.packages = lib.mkOption {
      type = types.lazyAttrsOf (types.lazyAttrsOf srcPatchType);
      default = { };
    };
    options.patches = patchesOption;
    options.src = srcOption;
  };

  srcPatchType = submoduleType {
    options.patches = patchesOption;
    options.src = srcOption;
  };

  patchesOption = lib.mkOption {
    type = types.listOf srcType;
    default = [ ];
  };

  srcOption = lib.mkOption { type = srcType; };

  srcType = submoduleType {
    options.hash = lib.mkOption { type = types.str; };
    options.url = lib.mkOption { type = types.str; };
  };

in

{
  options.rocq = submoduleOption {
    options.sources = lib.mkOption { type = types.lazyAttrsOf rocqVersionType; };
  };
}
