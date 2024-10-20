{ lib, ... }:
{
  networking = {
    timeServers = lib.mkDefault [ "ntp.aliyun.com" ];
    nftables.enable = lib.mkDefault true;
    firewall.enable = lib.mkDefault true;
  };
}
