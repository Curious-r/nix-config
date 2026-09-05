let
  sources = import ../npins;

  overlays = import ../overlays;

  machines = import ./machines.nix;

  thirdPartyPackages = import ../pkgs/third-party.nix {
    inherit sources;
  };
in
{
  inherit
    machines
    overlays
    sources
    thirdPartyPackages
    ;
}
