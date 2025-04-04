{ lib, ... }:
{
  boot.initrd.systemd.enable = lib.mkDefault true;
}
