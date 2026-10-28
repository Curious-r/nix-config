{
  lib,
  ...
}:
{
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  imports = [
    ../common/optional/disko/primary/efi-btrfs.nix
  ];

  hardware.facter.reportPath = ./facter.json;

  disko.devices.disk.primary.device = "/dev/disk/by-id/ata-TOSHIBA_SLC_128GB_SN201601176";
}
