let
  sources = import ../npins;

  overlays = import ../overlays;
in
{
  inherit
    overlays
    sources
    ;
}
