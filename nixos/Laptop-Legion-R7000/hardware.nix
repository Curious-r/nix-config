{ sources, ... }:
{
  imports = [
    # Hardware configuration from the community collection.
    (import "${sources.nixos-hardware}/lenovo/legion/15arh05h")
  ];
  hardware.facter.reportPath = ./facter.json;

  disko.primary = {
    diskId = "nvme-SAMSUNG_MZVLB512HBJQ-000L2_S4DYNF0N449629";
    swapSize = "16G";
  };
}
