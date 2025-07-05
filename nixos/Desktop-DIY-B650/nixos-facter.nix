{ inputs, ... }:
{
  imports = [ inputs.nixos-facter-modules.nixosModules.facter ];
  facter.reportPath = ./facter.json;
  networking.useNetworkd = false;
}
