{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.catppuccin-cursors.latteLight
  ];
}
