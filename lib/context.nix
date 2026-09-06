let
  sources = import ../npins;

  overlays = import ../overlays;

  machines = import ./machines.nix;
in
{
  inherit
    machines
    overlays
    sources
    ;
}
