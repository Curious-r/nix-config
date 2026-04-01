{ inputs, ... }:
{
  imports = [
    # hardware config from community collection
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
  ];
  hardware = {
    facter.reportPath = ./facter.json;
    raspberry-pi."4".apply-overlays-dtmerge.enable = true;
    deviceTree = {
      enable = true;
      filter = "*rpi-4-*.dtb";
    };
  };
}
