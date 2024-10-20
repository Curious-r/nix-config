# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).
{ pkgs, ... }:
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # ./homeserver.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.consoleMode = "auto";
  boot.loader.efi.canTouchEfiVariables = true;

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
      allowedTCPPorts = [ 22 ];
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

  # Sops-nix
  # sops = {
  #   defaultSopsFile = ./secrets/secrets.yaml;
  #   defaultSopsFormat = "yaml";
  #   age.keyFile = "/home/curious/.config/sops/age/keys.txt";
  #   secrets = {
  #     example-key = {};
  #     "myservice/my_subdir/my_secret" = {
  #       owner = "sometestservice";
  #     };
  #   };
  # };

  # Configure keymap in X11
  # services.xserver.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    gitoxide
    wget
    zellij
    bottom
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Set dae daemon.
  # services.dae = {
  #   enable = false;
  #   openFirewall = {
  #     enable = true;
  #     port = 12345;
  #   };
  #   configFile = "/home/curious/nix-config/nixos/Server-Lenovo-G480/config.dae";
  # };

  # services.desktopManager.cosmic.enable = true;
  # services.displayManager.cosmic-greeter.enable = true;

  # Enable docker.
  # virtualisation.docker.enable = true;
  # virtualisation.docker.storageDriver = "btrfs";

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
