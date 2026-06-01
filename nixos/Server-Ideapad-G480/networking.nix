{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.impala
  ];
  networking = {
    hostName = "Server-Ideapad-G480"; # Define your hostname.
    timeServers = [ "ntp.aliyun.com" ];
    wireless.iwd.enable = true;
    useNetworkd = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        39710
        8123
        8501
        9876
      ];
      allowedUDPPorts = [ 39710 ];
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
  systemd.network = {
    networks."10-lan" = {
      matchConfig.Name = "enp2s0";

      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };

      ipv6AcceptRAConfig = {
        Token = "::fade:480";
      };
    };
  };
}
