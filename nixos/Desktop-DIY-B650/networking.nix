{ ... }:
{
  networking = {
    hostName = "Desktop-DIY-B650"; # Define your hostname.
    networkmanager = {
      enable = true; # Enables NetworkManager, which will manage networking
    };
    timeServers = [ "ntp.aliyun.com" ];
    nftables = {
      enable = true;
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
      ];
      allowedUDPPorts = [ ];
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
