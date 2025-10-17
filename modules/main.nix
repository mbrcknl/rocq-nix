{
  config,
  lib,
  nixpkgs,
  rocq-nix-lib,
  ...
}:

let
  inherit (lib) types;
  inherit (rocq-nix-lib)
    flakeAppType
    mkOptionDefault
    submoduleOptionDefault
    ;

  mkPkgsDefault =
    system:
    lib.mkOption {
      type = types.pkgs;
      default = import nixpkgs {
        inherit system;
        inherit (config.nixpkgs) overlays;
      };
    };

  buildPackages =
    system: pathSets:
    let
      pkgs = config.nixpkgs.pkgs.${system};
      linkPathSet =
        setName: pathSet:
        let
          linkPath = pathName: path: ''
            mkdir -p "$out/${setName}"
            ln -s "${path}" "$out/${setName}/${pathName}"'';
        in
        lib.concatStringsSep "\n" (lib.mapAttrsToList linkPath pathSet);
      package = pkgs.stdenvNoCC.mkDerivation {
        name = "check-packages-build";
        buildCommand = lib.concatStringsSep "\n" (lib.mapAttrsToList linkPathSet pathSets);
      };
    in
    package;

  overlayType = types.listOf (types.functionTo (types.functionTo types.pkgs));
in

{
  options.nixpkgs = submoduleOptionDefault {
    options.overlays = mkOptionDefault overlayType [ ];
    options.pkgs = submoduleOptionDefault {
      freeformType = types.lazyAttrsOf types.pkgs;
      options = lib.genAttrs config.systems mkPkgsDefault;
    };
  };

  options.flake = submoduleOptionDefault {
    options.packages = lib.mkOption {
      type = types.lazyAttrsOf (types.lazyAttrsOf types.package);
      default = { };
    };
    options.apps = lib.mkOption {
      type = types.lazyAttrsOf (types.lazyAttrsOf flakeAppType);
      default = { };
    };
    options.checks = lib.mkOption {
      type = types.lazyAttrsOf (types.lazyAttrsOf types.package);
      default = { };
    };
    options.lib = submoduleOptionDefault {
      options.nixpkgs = submoduleOptionDefault {
        options.overlays = mkOptionDefault overlayType config.nixpkgs.overlays;
        options.pkgs = submoduleOptionDefault {
          freeformType = types.lazyAttrsOf types.pkgs;
          options = lib.mapAttrs (_: mkOptionDefault types.pkgs) config.nixpkgs.pkgs;
        };
      };
    };
    options.formatter = lib.mkOption {
      type = types.lazyAttrsOf types.pathInStore;
      default = { };
    };
  };

  config.flake.checks = lib.genAttrs config.systems (system: {
    packages-build = lib.mkDefault (
      buildPackages system {
        packages = config.flake.packages.${system};
        apps = lib.mapAttrs (_: app: app.program) config.flake.apps.${system};
      }
    );
  });
}
