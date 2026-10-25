{ pkgs, lib, ... }:
{
  boot = {
    kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
    initrd.systemd = {
      emergencyAccess = lib.mkDefault true;
    };
    supportedFilesystems = {
      ntfs = lib.mkDefault true;
      exfat = lib.mkDefault true;
    };
  };
  system = {
    nixos-init.enable = true;
    etc.overlay.enable = true;
  };
}
