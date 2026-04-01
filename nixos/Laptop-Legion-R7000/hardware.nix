{ inputs, ... }:
{
  imports = [
    # hardware config from community collection
    inputs.nixos-hardware.nixosModules.lenovo-legion-15arh05h
  ];
  hardware.facter.reportPath = ./facter.json;
}
