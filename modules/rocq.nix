{
  config,
  inputs,
  lib,
  rocq-nix-lib,
  ...
}:

let
  inherit (lib) types;
  inherit (rocq-nix-lib)
    concatMapAttrs
    concatMapAttrsToList
    deferredModuleType
    flakeAppType
    getFlakeGitInput
    mkOptionDefault
    mkBoolDefault
    mkStringDefault
    mkStringsDefault
    mkRelativePathDefault
    mkStorePathDefault
    mkPackageDefault
    mkPackagesDefault
    mkRocq
    submoduleOption
    submoduleOptionDefault
    submoduleType
    ;

  hyphenate = lib.replaceStrings [ "." ] [ "-" ];

  eachRocqModule =
    {
      config,
      pkgs,
      rocq,
      ...
    }:
    let
      devModule =
        dev@{ config, ... }:
        let
          rocqWithPackages = rocq.withPackages {
            libraries = config.env.lib;
            packages = config.env.bin;
          };
          vsrocqPackagesModule =
            { config, name, ... }:
            {
              options.vsrocq = mkPackageDefault rocqWithPackages.vsrocq.${name};
              options.settings-json = mkPackageDefault (
                config.vsrocq.mkSettingsJSON dev.config.vscode.settings.json
              );
            };
          mkVSCodeSettingsExport = version: package: {
            name = "vsrocq-${hyphenate version}-settings-json";
            value = mkPackageDefault package.settings-json;
          };
          vscodeSettingsExports = lib.mapAttrs' mkVSCodeSettingsExport config.packages.vsrocq;
          exportPackages = vscodeSettingsExports // {
            dir-locals-el = mkPackageDefault config.packages.dir-locals-el;
            envrc = mkPackageDefault config.packages.envrc;
            mise-toml = mkPackageDefault config.packages.mise-toml;
          };
        in
        {
          options.env = submoduleOptionDefault {
            options.lib = mkPackagesDefault [ ];
            options.bin = mkPackagesDefault [
              pkgs.gnumake
              rocq.ocamlPackages.dune_3
              rocq.ocamlPackages.ocaml
              rocq.coqPackages.coq
            ];
          };
          options.envrc = submoduleOptionDefault {
            options.path = mkRelativePathDefault ".envrc";
          };
          options.mise-toml = submoduleOptionDefault {
            options.path = mkRelativePathDefault ".config/mise/conf.d/rocq-nix.toml";
          };
          options.emacs = submoduleOptionDefault {
            options.dir-locals = submoduleOptionDefault {
              options.path = mkRelativePathDefault ".dir-locals.el";
              options.el = mkStringDefault ''
                ((coq-mode . ((coq-prog-name . "${config.packages.coqtop}"))))
              '';
            };
          };
          options.vscode = submoduleOptionDefault {
            options.settings = submoduleOptionDefault {
              options.path = mkRelativePathDefault ".vscode/settings.json";
              options.json = submoduleOptionDefault {
                freeformType = types.lazyAttrsOf types.anything;
                options."explorer.excludeGitIgnore" = mkBoolDefault false;
                options."files.exclude" = submoduleOptionDefault {
                  freeformType = types.lazyAttrsOf types.bool;
                  options."**/*.glob" = mkBoolDefault true;
                  options."**/*.install" = mkBoolDefault true;
                  options."**/*.vo" = mkBoolDefault true;
                  options."**/*.vok" = mkBoolDefault true;
                  options."**/*.vos" = mkBoolDefault true;
                  options."**/.*.aux" = mkBoolDefault true;
                  options."**/.*.cache" = mkBoolDefault true;
                  options."**/.Makefile.coq.d" = mkBoolDefault true;
                  options."**/.coq-native" = mkBoolDefault true;
                  options."**/_build" = mkBoolDefault true;
                  options."**/_opam" = mkBoolDefault true;
                  options.".rocq-nix" = mkBoolDefault true;
                };
                options."search.useIgnoreFiles" = mkBoolDefault false;
                options."vsrocq.args" = mkStringsDefault [ ];
              };
            };
          };
          options.packages = submoduleOptionDefault {
            options.envrc = mkPackageDefault rocqWithPackages.envrc;
            options.mise-toml = mkPackageDefault rocqWithPackages.miseTOML;
            options.coqtop = mkStorePathDefault rocqWithPackages.coqtop;
            options.dir-locals-el = mkPackageDefault (
              pkgs.writeText "rocq-${rocq.version}-dir-locals.el" config.emacs.dir-locals.el
            );
            options.vsrocq = submoduleOptionDefault {
              freeformType = types.lazyAttrsOf (submoduleType vsrocqPackagesModule);
              options = lib.flip lib.mapAttrs rocqWithPackages.vsrocq (
                _: _: submoduleOptionDefault vsrocqPackagesModule
              );
            };
          };
          options.exports = submoduleOptionDefault {
            options.packages = submoduleOptionDefault {
              freeformType = types.lazyAttrsOf types.package;
              options = exportPackages;
            };
          };
        };
    in
    {
      options.packages = mkOptionDefault (types.lazyAttrsOf types.package) { };
      options.apps = mkOptionDefault (types.lazyAttrsOf flakeAppType) { };
      options.checks = mkOptionDefault (types.lazyAttrsOf types.package) { };
      options.lib = mkOptionDefault (types.lazyAttrsOf types.anything) { };

      options.dev = submoduleOptionDefault devModule;

      options.exports = submoduleOptionDefault {
        options.packages = submoduleOptionDefault {
          freeformType = types.lazyAttrsOf types.package;
          options = lib.mapAttrs (_: mkPackageDefault) (config.dev.exports.packages // config.packages);
        };
        options.apps = submoduleOptionDefault {
          freeformType = types.lazyAttrsOf flakeAppType;
          options = lib.mapAttrs (_: mkOptionDefault flakeAppType) config.apps;
        };
        options.checks = submoduleOptionDefault {
          freeformType = types.lazyAttrsOf types.package;
          options = lib.mapAttrs (_: mkPackageDefault) config.checks;
        };
      };
    };

  applyEachVersion =
    modules:
    {
      system,
      pkgs,
      rocqVersion,
      rocqSources,
      ...
    }:
    let
      getInput' =
        name: flake:
        let
          foreach = flake.lib.rocq.versions.foreach or null;
        in
        lib.optional (foreach != null) {
          inherit name;
          value = foreach {
            inherit
              system
              pkgs
              rocqVersion
              rocqSources
              ;
          };
        };
      args.config._module.args = {
        inputs' = concatMapAttrs getInput' inputs;
        rocq = mkRocq pkgs rocqVersion rocqSources;
        inherit pkgs rocqSources;
      };
      eval = lib.evalModules {
        modules = [ args ] ++ lib.toList modules;
        prefix = [
          "rocq"
          "versions"
          "foreach"
          system
          rocqVersion
        ];
        specialArgs = {
          inherit system rocqVersion;
        };
      };
    in
    eval.config;

  mkRocqConfig =
    system: rocqVersion: supported:
    lib.optional supported {
      name = rocqVersion;
      value = lib.mkOption {
        type = types.unspecified;
        default = config.rocq.versions.foreach {
          inherit system rocqVersion;
          pkgs = config.nixpkgs.pkgs.${system};
          rocqSources = config.rocq.sources.${rocqVersion};
        };
      };
    };

  mkFlakeAttrs =
    {
      getRocqVersionAttrs ? _: { },
      getSystemAttrs ? _: { },
    }:
    let
      mkFlakeAttr =
        system: rocqConfigs:
        let
          systemAttrs = lib.attrsToList (getSystemAttrs system);
          mkRocqConfig =
            rocqVersion: rocqConfig:
            let
              mkVersioned = name: value: {
                name = "rocq-${hyphenate rocqVersion}-${name}";
                value = lib.mkDefault value;
              };
            in
            lib.mapAttrsToList mkVersioned (getRocqVersionAttrs rocqConfig.exports);
        in
        lib.listToAttrs (concatMapAttrsToList mkRocqConfig rocqConfigs ++ systemAttrs);
    in
    lib.mapAttrs mkFlakeAttr config.flake.lib.rocq.versions.outputs;

  rocqNixCommandConfig = { };

  mkRocqNixCommand =
    system:
    let
      pkgs = config.nixpkgs.pkgs.${system};
      python = "${pkgs.python3}/bin/python";
      configJSON = pkgs.writers.writeJSON "rocq-nix-config.json" rocqNixCommandConfig;
      command = pkgs.stdenvNoCC.mkDerivation {
        name = "rocq-nix";
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        passAsFile = [
          "compilePy"
          "rocqNixPy"
        ];
        compilePy = ''
          from py_compile import compile
          compile("rocq-nix-command.py", cfile="rocq-nix.pyc", doraise=True)
        '';
        rocqNixPy = lib.readFile ../command/rocq-nix-command.py;
        buildCommand = ''
          mkdir -p "$out/bin" "$out/lib" "$out/etc"
          mv "$rocqNixPyPath" rocq-nix-command.py
          "${python}" "$compilePyPath"
          mv rocq-nix.pyc "$out/lib"
          cp "${configJSON}" "$out/etc/config.json"
          makeWrapper "${python}" "$out/bin/rocq-nix" \
            --add-flag "$out/lib/rocq-nix.pyc"
        '';
      };
    in
    command;

  rocqNixCommand = lib.genAttrs config.systems mkRocqNixCommand;

  mkRocqNixPackages = system: {
    rocq-nix = rocqNixCommand.${system};
  };

  gitSourceOption = submoduleOptionDefault {
    options.url = lib.mkOption { type = types.str; };
    options.rev = lib.mkOption { type = types.str; };
  };

  devSourceType = types.attrTag {
    input = lib.mkOption { type = types.listOf types.str; };
    git = gitSourceOption;
  };

  devSourceResolvedType = types.attrTag {
    git = gitSourceOption;
  };

  resolveSource =
    source:
    lib.mkOption {
      type = devSourceResolvedType;
      default =
        if source ? git then
          source
        else if source ? input then
          { git = getFlakeGitInput inputs.self source.input; }
        else
          throw "Unknown source type";
    };
in

{
  options.rocq = submoduleOptionDefault {
    options.dev = submoduleOptionDefault {
      options.sources = lib.mkOption {
        type = types.lazyAttrsOf devSourceType;
        default = { };
      };
    };
    options.versions = submoduleOptionDefault {
      options.default = lib.mkOption { type = types.str; };
      options.supported = submoduleOptionDefault {
        freeformType = types.lazyAttrsOf types.bool;
        options = lib.flip lib.mapAttrs config.rocq.sources (
          rocqVersion: _: mkBoolDefault (rocqVersion == config.rocq.versions.default)
        );
      };
      options.foreach = lib.mkOption {
        type = deferredModuleType eachRocqModule;
        apply = applyEachVersion;
        default = _: { };
      };
    };
  };

  options.flake = submoduleOption {
    options.lib = submoduleOption {
      options.rocq = submoduleOptionDefault {
        options.dev = submoduleOptionDefault {
          options.sources = submoduleOptionDefault {
            freeformType = types.lazyAttrsOf devSourceResolvedType;
            options = lib.mapAttrs (_: resolveSource) config.rocq.dev.sources;
          };
        };
        options.versions = submoduleOptionDefault {
          options.foreach = lib.mkOption {
            type = deferredModuleType eachRocqModule;
            apply = applyEachVersion;
            default = config.rocq.versions.foreach;
          };
          options.outputs = submoduleOptionDefault {
            freeformType = types.lazyAttrsOf (types.lazyAttrsOf types.unspecified);
            options = lib.genAttrs config.systems (
              system:
              submoduleOptionDefault {
                freeformType = types.lazyAttrsOf types.unspecified;
                options = concatMapAttrs (mkRocqConfig system) config.rocq.versions.supported;
              }
            );
          };
        };
      };
    };
  };

  config.flake = {
    config.packages = mkFlakeAttrs {
      getRocqVersionAttrs = exports: exports.packages;
      getSystemAttrs = mkRocqNixPackages;
    };
    config.apps = mkFlakeAttrs {
      getRocqVersionAttrs = exports: exports.apps;
    };
    config.checks = mkFlakeAttrs {
      getRocqVersionAttrs = exports: exports.checks;
    };
  };
}
