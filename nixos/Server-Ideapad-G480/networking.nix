{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.impala
  ];
  networking = {
    hostName = "Server-Ideapad-G480"; # Define your hostname.
    timeServers = [ "ntp.aliyun.com" ];
    nftables.enable = true;
    wireless.iwd.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        7931
        8123
        9876
      ];
      allowedUDPPorts = [ 7931 ];
      # checkReversePath = "loose";
      logReversePathDrops = true;
      logRefusedPackets = true;
    };
    # Configure network proxy if necessary
    # proxy = {
    #   default = "socks://192.168.1.8:7890";
    #   noProxy = "127.0.0.1,localhost,internal.domain";
    # };
  };
}
