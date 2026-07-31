{ lib, ... }:
{
  programs.niri.enable = true;
  xdg.portal.config.niri."org.freedesktop.impl.portal.Secret" = lib.mkForce "oo7-portal";
}
