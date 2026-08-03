{ pkgs, ... }:
{
  xdg.configFile."niri/config.kdl".source = ./config.kdl;
  xdg.configFile."niri/animations".source = ./animations;
  home.packages = [
    pkgs.xwayland-satellite
  ];
}
