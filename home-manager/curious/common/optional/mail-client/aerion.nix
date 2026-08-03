{ pkgs, ... }:
{
  home.packages = [ (pkgs.aerion.override { withOAuth = true; }) ];
}
