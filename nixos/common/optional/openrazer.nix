{ pkgs, ... }:
{
  hardware.openrazer = {
    enable = true;
    users = [ "curious" ];
  };
  environment.systemPackages = [
    pkgs.polychromatic
  ];
}
