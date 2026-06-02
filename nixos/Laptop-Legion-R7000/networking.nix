{ ... }:
{
  networking = {
    hostName = "Laptop-Legion-R7000"; # Define your hostname.

    timeServers = [ "ntp.aliyun.com" ];

    wireless.iwd.enable = true;
    useNetworkd = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [ ];
      allowedUDPPorts = [ ];
      # checkReversePath = "loose";
      logReversePathDrops = true;
      logRefusedPackets = true;
    };
  };

  systemd.network = {
    networks."10-lan" = {
      matchConfig.Name = "eno1";

      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };

      ipv6AcceptRAConfig = {
        Token = "::fade:7000";
      };
    };
  };
}
