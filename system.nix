let
  sources = import ./npins;
  evalNixos = import "${sources.nixpkgs}/nixos/lib/eval-config.nix";

  overlays = {
    additions = final: _prev: import ./pkgs final;
    modifications = _final: _prev: { };
  };

  project = {
    _type = "flake";
    outPath = ./.;
    overlays = overlays;
    homeManagerModules = import ./modules/home-manager;
    nixosModules = import ./modules/nixos;
    vaultix.cache = "./secrets/cache";
  };

  mkInputs =
    pkgs:
    let
      lanzaboote = import sources.lanzaboote { inherit pkgs; };
      zenBrowser = import sources.zen-browser { inherit pkgs; };
      thirdPartyPackages = import ./third-party-packages.nix { inherit sources; };
    in
    {
      inherit (sources) nixpkgs;

      home-manager = {
        inherit (sources.home-manager) outPath;
        nixosModules.home-manager = import "${sources.home-manager}/nixos";
      };

      nixos-hardware = {
        inherit (sources.nixos-hardware) outPath;
        nixosModules.lenovo-legion-15arh05h = import "${sources.nixos-hardware}/lenovo/legion/15arh05h";
      };

      vaultix = {
        inherit (sources.vaultix) outPath;
        nixosModules.default = { pkgs, ... }: {
          imports = [ "${sources.vaultix}/module" ];
          vaultix.package = thirdPartyPackages.vaultix pkgs;
        };
      };

      pam-fido-remote = {
        inherit (sources.pam-fido-remote) outPath;
        nixosModules.default = {
          imports = [
            (import "${sources.pam-fido-remote}/nix/modules/nixos/fido-remote.nix" {
              flake.mkPackagesFor = hostPkgs: {
                pam-fido-remote = thirdPartyPackages.pam-fido-remote hostPkgs;
              };
            })
          ];
        };
      };

      preservation = {
        inherit (sources.preservation) outPath;
        nixosModules.preservation = import "${sources.preservation}/module.nix";
      };

      disko = {
        inherit (sources.disko) outPath;
        nixosModules.disko = import "${sources.disko}/module.nix";
      };

      lanzaboote = {
        inherit (sources.lanzaboote) outPath;
        nixosModules.lanzaboote = lanzaboote.nixosModules.lanzaboote;
      };

      zen-browser = {
        inherit (sources.zen-browser) outPath;
        packages.${pkgs.stdenv.hostPlatform.system} = zenBrowser;
      };

      dms-plugin-registry = {
        inherit (sources.dms-plugin-registry) outPath;
        nixosModules.default = import "${sources.dms-plugin-registry}/nix/module.nix";
      };
    };

  machines = import ./machines.nix;

  mkSystem =
    name: machine:
    let
      pkgs = import sources.nixpkgs {
        localSystem.system = machine.system;
        overlays = builtins.attrValues overlays;
        config.allowUnfree = true;
      };
      inputs = mkInputs pkgs;
    in
    evalNixos {
      inherit pkgs;
      system = machine.system;
      specialArgs = {
        inherit inputs project;
        self = project;
      }
      // machine.specialArgs;
      modules = [
        { nixpkgs.flake.source = sources.nixpkgs.outPath; }
        {
          # The host package set is constructed once above. NixOS asserts that
          # legacy nixpkgs.config must not be merged into such an instance.
          nixpkgs.config = pkgs.lib.mkForce { };
        }
        ./nixos/common/core
        machine.module or (./nixos + "/${name}")
      ];
    };
in
builtins.mapAttrs mkSystem machines
