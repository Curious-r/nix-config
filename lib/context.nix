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

  machines = import ./machines.nix;

  thirdPartyPackages = import ../pkgs/third-party.nix {
    inherit sources;
  };
in
{
  inherit
    machines
    overlays
    project
    sources
    thirdPartyPackages
    ;
}
