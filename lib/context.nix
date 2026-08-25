let
  sources = import ../npins;

  overlays = import ../overlays;

  project = {
    _type = "flake";
    outPath = ./..;
    overlays = overlays;
    homeManagerModules = import ../modules/home-manager;
    nixosModules = import ../modules/nixos;
    vaultix = import ../secrets/vaultix.nix // {
      defaultSecretDirectory = "./secrets";
    };
  };

  mkInputs =
    pkgs:
    let
      lanzaboote = import sources.lanzaboote { inherit pkgs; };
      zenBrowser = import sources.zen-browser { inherit pkgs; };
      thirdPartyPackages = import ../pkgs/third-party.nix { inherit sources; };
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
in
{
  inherit
    machines
    mkInputs
    overlays
    project
    sources
    ;
}
