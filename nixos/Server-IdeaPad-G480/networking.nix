{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.impala
  ];

  networking = {
    hostName = "Server-IdeaPad-G480"; # Define your hostname.

    timeServers = [ "ntp.aliyun.com" ];

    wireless.iwd.enable = true;
    useNetworkd = true;
    nftables.enable = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [
        39710
        8123
        8501
        9876
        7881 # LiveKit: ICE-TCP 降级应急视频传输通道
      ];

      allowedUDPPorts = [ 39710 ];

      # 使用 Ranges 来批量放行连续的端口段
      allowedUDPPortRanges = [
        {
          from = 50100;
          to = 50200;
        } # LiveKit: WebRTC UDP 核心音视频流直连通道
      ];

      # checkReversePath = "loose";
      logReversePathDrops = true;
      logRefusedPackets = true;
    };
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
