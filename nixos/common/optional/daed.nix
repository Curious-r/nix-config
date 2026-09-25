{ nixosModules, pkgs, ... }:
{
  imports = [ nixosModules.daed ];
  services.daed = {
    enable = true;
    package = pkgs.curious.daed;
    openFirewall = {
      enable = true;
      port = 12345;
    };
  };
}
