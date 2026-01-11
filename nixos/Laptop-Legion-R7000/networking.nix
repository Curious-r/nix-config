{ ... }:
{
  networking = {
    hostName = "Laptop-Legion-R7000"; # Define your hostname.
    networkmanager = {
      enable = true; # Enables NetworkManager, which will manage networking
      wifi.backend = "iwd";
    };
    timeServers = [ "ntp.aliyun.com" ];
    firewall = {
      enable = true;
      allowedTCPPorts = [ ];
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
  services.firewalld.enable = true;
}
