{ lib, ... }:
{
  boot.initrd.systemd.enable = lib.mkDefault true;
  boot.initrd.systemd.emergencyAccess = lib.mkDefault true;
}
