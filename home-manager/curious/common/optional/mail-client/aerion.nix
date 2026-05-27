{ pkgs, ... }:
{
  home.packages = with pkgs; [ (aerion.override { withOAuth = true; }) ];
}
