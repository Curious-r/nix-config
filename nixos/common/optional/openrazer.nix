{ pkgs, ... }:
{
  hardware.openrazer = {
    enable = true;
    users = [ "curious" ];
  };
  environment.systemPackages = with pkgs; [
    polychromatic
  ];
}
