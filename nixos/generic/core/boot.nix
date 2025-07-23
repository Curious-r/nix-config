{ pkgs, lib, ... }:
{
  boot = {
    kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
    initrd.systemd = {
      enable = lib.mkDefault true;
      emergencyAccess = lib.mkDefault true;
    };
  };
}
