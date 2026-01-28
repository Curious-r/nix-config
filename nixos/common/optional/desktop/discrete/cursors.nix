{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    catppuccin-cursors.latteLight
  ];
}
