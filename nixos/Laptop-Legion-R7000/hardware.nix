{
  lib,
  sources,
  ...
}:
{
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  imports = [
    ../common/optional/disko/primary/efi-btrfs.nix
    # Hardware configuration from the community collection.
    (import "${sources.nixos-hardware}/lenovo/legion/15arh05h")
  ];
  hardware.facter.reportPath = ./facter.json;

  disko.devices.disk.primary = {
    device = "/dev/disk/by-id/nvme-SAMSUNG_MZVLB512HBJQ-000L2_S4DYNF0N449629";
    content.partitions.main.content.subvolumes."@swap".swap.swapfile.size = "16G";
  };
}
