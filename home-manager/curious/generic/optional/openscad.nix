{ pkgs, ... }:
{
  home.packages = with pkgs; [
    openscad-unstable
  ];
}
