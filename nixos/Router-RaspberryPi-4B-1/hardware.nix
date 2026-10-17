{ lib, ... }:
{
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  imports = [
    ../common/optional/disko/primary/efi-btrfs.nix
  ];

  hardware = {
    facter.reportPath = ./facter.json;
  };

  disko.devices.disk.primary = {
    device = "/dev/disk/by-id/usb-SMI_USB_DISK_CCYYMMDDHHmmSSXM5IKH-0:0";
    content.partitions.main.content.subvolumes."@swap".swap.swapfile.size = "1G";
  };
}
