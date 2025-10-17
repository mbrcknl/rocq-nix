{
  lib,
  nixpkgs,
  rocq-nix-config,
  rocq-nix-lib,
  treefmt-nix,
}:

let
  inherit (lib) types;

  concatMapAttrsToList = f: set: lib.concatLists (lib.mapAttrsToList f set);
  concatMapAttrs = f: set: lib.listToAttrs (concatMapAttrsToList f set);

  mkOptionDefault =
    type: default:
    lib.mkOption {
      inherit type default;
    };

  mkBoolDefault = mkOptionDefault types.bool;
  mkStringDefault = mkOptionDefault types.str;
  mkStringsDefault = mkOptionDefault (types.listOf types.str);
  mkRelativePathDefault = mkOptionDefault relativePathType;
  mkStorePathDefault = mkOptionDefault types.pathInStore;
  mkPackageDefault = mkOptionDefault types.package;
  mkPackagesDefault = mkOptionDefault (types.listOf types.package);

  relativePathType = types.pathWith {
    inStore = false;
    absolute = false;
  };

  submoduleType =
    module:
    lib.types.submoduleWith {
      modules = [ module ];
    };

  submoduleOption =
    module:
    lib.mkOption {
      type = submoduleType module;
    };

  submoduleOptionDefault =
    module:
    lib.mkOption {
      type = submoduleType module;
      default = { };
    };

  deferredModuleType =
    module:
    lib.types.deferredModuleWith {
      staticModules = [ module ];
    };

  flakeAppType = submoduleType {
    options.type = lib.mkOption {
      type = types.enum [ "app" ];
      default = "app";
    };
    options.program = lib.mkOption {
      type = types.pathInStore;
    };
    options.meta = lib.mkOption {
      type = types.lazyAttrsOf types.raw;
      default = { };
    };
  };

  getFlakeInput =
    flake:
    let
      lockFile = lib.importJSON (flake + "/flake.lock");
      inherit (lockFile) nodes;
      root = nodes.${lockFile.root};
      getInput = spec: if lib.isList spec then getPath root spec else nodes.${spec};
      getPath =
        node: path:
        if path == [ ] then node else getPath (getInput node.inputs.${lib.head path}) (lib.tail path);
    in
    getPath root;

  getFlakeGitInput =
    flake: input:
    let
      inherit (getFlakeInput flake input) locked;
      githubHost = locked.host or "github.com";
      gitlabHost = locked.host or "gitlab.com";
      githubUrl = "https://${githubHost}/${locked.owner}/${locked.repo}.git";
      gitlabUrl = "https://${gitlabHost}/${locked.owner}/${locked.repo}.git";
      url =
        if locked.type == "git" then
          locked.url
        else if locked.type == "github" then
          githubUrl
        else if locked.type == "gitlab" then
          gitlabUrl
        else
          throw "Unsupported source type";
    in
    {
      inherit (locked) rev;
      inherit url;
    };

  # Environment variables used by Rocq to find libraries

  rocqEnvVars = [
    "CAML_LD_LIBRARY_PATH"
    "OCAMLPATH"
    "COQPATH"
    "ROCQPATH"
  ];

  # Flake constructor

  mkFlake =
    {
      inputs,
      specialArgs ? { },
      ...
    }:
    module:
    let
      result = lib.evalModules {
        modules = [
          module
          argsModule
          (systemsModule lib.mkDefault)
          (sourcesModule lib.mkDefault)
          ../modules/main.nix
          ../modules/rocq.nix
          ../modules/treefmt.nix
        ];
        specialArgs = {
          inherit inputs rocq-nix-lib;
        }
        // specialArgs;
      };
    in
    result.config.flake;

  argsModule._module.args = {
    inherit nixpkgs treefmt-nix;
  };

  systemsModule = setPriority: {
    options.systems = lib.mkOption { type = types.listOf types.str; };
    config.systems = setPriority rocq-nix-config.systems;
  };

  sourcesModule =
    setPriority:
    let
      inherit (rocq-nix-config.sources) rocq rocq-packages;
    in
    {
      imports = [ ../modules/sources.nix ];
      config.rocq.sources = mkRocqConfig setPriority rocq-packages rocq;
    };

  mkRocqConfig =
    setPriority: packagesVersionsConfig: rocqVersionsConfig:
    let
      rocqConfig = lib.mapAttrs getRocqVersionWithPackagesConfig rocqVersionsConfig;
      getRocqVersionWithPackagesConfig =
        rocqVersion: rocqVersionConfig:
        let
          rocqVersionConfig' = lib.mapAttrs (_: setPriority) rocqVersionConfig;
          packagesVersionsConfig' = concatMapAttrs getRocqPackageVersionsConfigMaybe packagesVersionsConfig;
          getRocqPackageVersionsConfigMaybe =
            packageName: packageVersionsConfig:
            let
              packageVersionsConfig' = concatMapAttrs getRocqPackageVersionConfigMaybe packageVersionsConfig;
              result = lib.optional (packageVersionsConfig' != { }) {
                name = packageName;
                value = packageVersionsConfig';
              };
            in
            result;
          getRocqPackageVersionConfigMaybe =
            packageVersion: packageVersionConfig:
            let
              rocqVersionExtraConfig = packageVersionConfig.rocq-versions.${rocqVersion} or null;
              packageVersionConfigClean = lib.removeAttrs packageVersionConfig [ "rocq-versions" ];
              packageVersionConfig' = lib.optional (!isNull rocqVersionExtraConfig) {
                name = packageVersion;
                value = lib.mapAttrs (_: setPriority) (mergeConfigs [
                  packageVersionConfigClean
                  rocqVersionExtraConfig
                ]);
              };
            in
            packageVersionConfig';
          rocqVersionPackagesConfig =
            if packagesVersionsConfig' != { } then { packages = packagesVersionsConfig'; } else { };
        in
        rocqVersionConfig' // rocqVersionPackagesConfig;
    in
    rocqConfig;

  mergeConfigs =
    configs:
    if lib.length configs <= 1 then
      lib.head configs
    else if lib.all (c: lib.typeOf c == "set") configs then
      lib.zipAttrsWith (name: mergeConfigs) configs
    else if lib.all (c: lib.typeOf c == "list") configs then
      lib.concatLists configs
    else
      lib.last configs;

  # Functions for building Rocq, VSRocq, and environment config files

  fetchSource =
    pkgs:
    {
      src,
      patches ? [ ],
      ...
    }:
    {
      src = pkgs.fetchzip src;
      patches = map pkgs.fetchpatch patches;
    };

  mkRocq =
    pkgs: version: config:
    let
      inherit (fetchSource pkgs config) src patches;
      inherit (config) compatible-rocq-version;
      inherit (rocq-core) ocamlPackages;
      rocq-nixpkgs = pkgs.callPackage (nixpkgs + "/pkgs/applications/science/logic/rocq-core") {
        inherit (pkgs.ocaml-ng) ocamlPackages_4_14;
        version = "${src}";
        rocq-version = compatible-rocq-version;
      };
      rocq-core = rocq-nixpkgs.overrideAttrs {
        inherit patches src version;
        passthru = rocq-nixpkgs.passthru // {
          inherit coqPackages rocqPackages;
        };
      };
      rocqPackages = pkgs.mkRocqPackages rocq-core;
      coq-nixpkgs = pkgs.callPackage (nixpkgs + "/pkgs/applications/science/logic/coq") {
        inherit (pkgs.ocaml-ng)
          ocamlPackages_4_09
          ocamlPackages_4_10
          ocamlPackages_4_12
          ocamlPackages_4_14
          ;
        inherit rocqPackages;
        version = "${src}";
        coq-version = compatible-rocq-version;
      };
      coq = coq-nixpkgs.overrideAttrs {
        inherit patches src version;
        passthru = coq-nixpkgs.passthru // {
          inherit coqPackages;
        };
      };
      coqPackages = pkgs.mkCoqPackages coq;
      rocq = {
        inherit
          config
          coq
          coqPackages
          ocamlPackages
          pkgs
          rocq-core
          rocqPackages
          version
          ;
        withPackages = rocqWithPackages rocq;
        vsrocq = lib.mapAttrs (mkVSRocq rocq) config.packages.vsrocq;
        vsrocqWithLibs = libs: (lib.mapAttrs (_: vsrocq: vsrocq.withLibraries libs) rocq.vsrocq);
        mkWrapper = mkWrapper rocq;
        coqtopWithLibs = mkCoqtopWithLibs rocq;
        mkEnvrc = mkEnvrc rocq;
        mkMiseTOML = mkMiseTOML rocq;
        mkEnvJSON = mkEnvJSON rocq;
      };
    in
    rocq;

  rocqWithPackages =
    rocq:
    args@{
      libraries ? [ ],
      packages ? [ ],
    }:
    {
      coqtop = (rocq.coqtopWithLibs libraries).bin.coqtop;
      envrc = rocq.mkEnvrc args;
      miseTOML = rocq.mkMiseTOML args;
      envJSON = rocq.mkEnvJSON args;
      vsrocq = rocq.vsrocqWithLibs libraries;
      mkWrapper =
        {
          name,
          paths ? [ ],
          passthru ? { },
        }:
        rocq.mkWrapper {
          inherit
            name
            libraries
            packages
            paths
            passthru
            ;
        };
    };

  mkVSRocq =
    rocq: version: config:
    let
      inherit (rocq) coq pkgs ocamlPackages;
      vsrocq-pre = ocamlPackages.buildDunePackage {
        pname = "vsrocq-language-server";
        inherit (fetchSource pkgs config) patches src;
        inherit version;
        passthru = {
          inherit rocq;
          withLibraries = vsrocqWithLibraries vsrocq;
        };
        duneVersions = "3";
        nativeBuildInputs = [ coq ];
        buildInputs = [
          coq
          ocamlPackages.findlib
          ocamlPackages.ppx_sexp_conv
          ocamlPackages.ppx_optcomp
          ocamlPackages.ppx_import
          ocamlPackages.sexplib
          ocamlPackages.ppx_yojson_conv
          ocamlPackages.lsp
          ocamlPackages.sel
        ];
        preConfigure = ''
          cd language-server
        '';
        preBuild = ''
          make dune-files
        '';
      };
      vsrocq = vsrocq-pre.overrideAttrs {
        name = "vsrocq-language-server-${version}-rocq-${coq.version}";
      };
    in
    vsrocq;

  vsrocqWithLibraries =
    vsrocq: libraries:
    let
      inherit (vsrocq.rocq) coq pkgs;
      setPath = {
        "vsrocq.path" = "${wrapped.bin.vsrocqtop}";
      };
      settingsName = "rocq-${coq.version}-vsrocq-${vsrocq.version}-settings.json";
      mkSettingsJSON = settings: pkgs.writers.writeJSON settingsName (settings // setPath);
      wrapped = mkWrapper vsrocq.rocq {
        name = "${vsrocq.name}-wrapped";
        inherit libraries;
        paths = {
          vsrocqtop = "${vsrocq}/bin/vsrocqtop";
        };
        packages = [ ];
        passthru = {
          inherit mkSettingsJSON vsrocq;
        };
      };
    in
    wrapped;

  mkCoqtopWithLibs =
    rocq: libraries:
    let
      inherit (rocq) coq;
      wrapped = mkWrapper rocq {
        name = "rocq-${coq.version}-coqtop-wrapped";
        inherit libraries;
        paths = {
          coqtop = "${coq}/bin/coqtop";
        };
        packages = [ ];
        passthru = {
          inherit rocq;
        };
      };
    in
    wrapped;

  mkWrapper =
    rocq:
    args@{
      name,
      libraries ? [ ],
      packages ? [ ],
      paths ? { },
      passthru ? { },
    }:
    let
      inherit (rocq) coq pkgs rocq-core;
      inherit (rocq.ocamlPackages) ocaml findlib;
      setOptsVar = var: ''
        if [ -n "''${${var}+x}" ]; then
          opts+=(--suffix ${var} : "''$${var}")
        fi'';
      wrapPath = name: path: ''makeWrapper "${path}" "$out/bin/${name}" "''${opts[@]}"'';
      wrapPackage = package: ''
        (
          src_bin="${package}/bin"
          cd "$src_bin"
          for exe in *; do
            makeWrapper "$src_bin/$exe" "$out/bin/$exe" "''${opts[@]}"
          done
        )'';
      mkWrapperCommands = lib.concatLists [
        (map setOptsVar rocqEnvVars)
        (map wrapPackage packages)
        (lib.mapAttrsToList wrapPath paths)
      ];
      passthru.bin = lib.mapAttrs (name: _: "${wrapper}/bin/${name}") paths;
      wrapper = pkgs.stdenvNoCC.mkDerivation {
        inherit name;
        passthru = passthru // args.passthru;
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        buildInputs = [
          coq
          rocq-core
          ocaml
          findlib
        ]
        ++ libraries;
        buildCommand = ''
          mkdir -p $out/bin
          opts=()
          ${lib.concatStringsSep "\n" mkWrapperCommands}
        '';
      };
    in
    wrapper;

  mkEnvrc =
    rocq:
    {
      libraries ? [ ],
      packages ? [ ],
    }:
    let
      inherit (rocq) coq pkgs rocq-core;
      inherit (rocq.ocamlPackages) ocaml findlib;
      exportRocqVar = var: ''
        if [ -n "''${${var}+x}" ]; then
          echo "${var}=\"''$${var}\"" >> "$out"
          vars+=("${var}")
        fi'';
      PATH = lib.makeBinPath packages;
      exportPATH = ''
        echo 'PATH="${PATH}''${PATH:+:$PATH}"' >> "$out"
        vars+=("PATH")'';
      exportVars = lib.concatLists [
        (map exportRocqVar rocqEnvVars)
        (lib.optional (packages != [ ]) exportPATH)
      ];
      envrc = pkgs.stdenvNoCC.mkDerivation {
        name = "rocq-${coq.version}-envrc";
        buildInputs = [
          coq
          rocq-core
          ocaml
          findlib
        ]
        ++ libraries;
        buildCommand = ''
          touch "$out"
          vars=()
          ${lib.concatStringsSep "\n" exportVars}
          if [ -n "''${vars[*]}" ]; then
            echo "export ''${vars[*]}" >> "$out"
          fi
        '';
      };
    in
    envrc;

  mkEnvJSON =
    rocq:
    {
      libraries ? [ ],
      packages ? [ ],
    }:
    let
      inherit (rocq) coq pkgs rocq-core;
      inherit (rocq.ocamlPackages) ocaml findlib;
      pathBin = map (p: "${p}/bin") packages;
      pathJSON = pkgs.writers.writeJSON "path.json" pathBin;
      mkEnvJSON = pkgs.writeText "env.py" ''
        import json, os, sys
        env = {
          var: os.environ[var]
          for var in ${builtins.toJSON rocqEnvVars}
          if var in os.environ
        }
        with open("${pathJSON}") as path_json:
          path = json.load(path_json)
        json.dump({"env": env, "path": path}, sys.stdout, indent=2)
        print()
      '';
      envJSON = pkgs.stdenvNoCC.mkDerivation {
        name = "rocq-${coq.version}-env.json";
        buildInputs = [
          coq
          rocq-core
          ocaml
          findlib
        ]
        ++ libraries;
        buildCommand = ''
          "${pkgs.python3}/bin/python" "${mkEnvJSON}" > "$out"
        '';
      };
    in
    envJSON;

  mkMiseTOML =
    rocq: args:
    let
      inherit (rocq) pkgs;
      envJSON = mkEnvJSON rocq args;
      envPy = pkgs.writeText "env.py" ''
        import json, sys
        with open("${envJSON}") as env_json:
          env_in = json.load(env_json)
        env_out = env_in["env"]
        if env_in["path"]:
          env_out["_"] = {"path": env_in["path"]}
        json.dump({"env": env_out}, sys.stdout, indent=2)
      '';
      miseTOML = pkgs.stdenvNoCC.mkDerivation {
        name = "rocq-${rocq.coq.version}-mise.toml";
        buildCommand = ''
          "${pkgs.python3}/bin/python" "${envPy}" \
            | "${pkgs.remarshal}/bin/json2toml" \
            > "$out"
        '';
      };
    in
    miseTOML;
in
{
  inherit
    concatMapAttrs
    concatMapAttrsToList
    deferredModuleType
    fetchSource
    flakeAppType
    getFlakeInput
    getFlakeGitInput
    mergeConfigs
    mkFlake
    mkOptionDefault
    mkBoolDefault
    mkStringDefault
    mkStringsDefault
    mkRelativePathDefault
    mkStorePathDefault
    mkPackageDefault
    mkPackagesDefault
    mkRocq
    mkRocqConfig
    rocq-nix-config
    relativePathType
    sourcesModule
    submoduleOption
    submoduleOptionDefault
    submoduleType
    systemsModule
    ;
}
