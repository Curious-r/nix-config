# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).
{ pkgs, ... }:
{
  imports = [
    ../generic/core
    ../generic/optional/nix/substituters/mainland.nix
    ../generic/optional/disko/primary/efi-btrfs.nix
    ../generic/optional/preservation/curious/desktop.nix
    ../generic/optional/preservation/curious/firefox.nix
    ../generic/optional/preservation/curious/thunderbird.nix
    ../generic/optional/boot/plymouth.nix
    ../generic/optional/fonts.nix
    ../generic/optional/desktop.nix
    ../generic/optional/input-method.nix
    ../generic/optional/daed.nix
    ../generic/optional/nix/substituters/garnix.nix
    ../generic/optional/preservation/daed.nix
    ../generic/optional/steam.nix

    # Use nixos-facter for hardware config
    ./nixos-facter.nix

    ./boot.nix
    ./vaultix.nix
    ./networking.nix
  ];

  # Enable the X11 windowing system.
  # services.xserver.enable = true;

  # programs.yazi = {
  #   enable = true;
  #   package = inputs.yazi.packages.${pkgs.system}.default; # if you use overlays, you can omit this
  # };

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wget
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

  # services.desktopManager.cosmic.enable = true;
  # services.displayManager.cosmic-greeter.enable = true;

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
  system.stateVersion = "25.05"; # Did you read the comment?
}
