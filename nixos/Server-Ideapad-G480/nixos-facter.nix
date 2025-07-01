{ inputs, ... }:
{
  imports = [ inputs.nixos-facter-modules.nixosModules.facter ];
  facter.reportPath = ./facter.json;
  # networkd 有 bug，暂时关闭，等待 systemd 257.6 进入stable
  networking.useNetworkd = false;
}
