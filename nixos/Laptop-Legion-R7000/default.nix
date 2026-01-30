# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).
{ pkgs, inputs, ... }:
{
  imports = [
    ../common/core
    ../common/optional/nix/substituters/mainland.nix
    ../common/optional/disko/primary/efi-btrfs.nix
    ../common/optional/preservation/curious/desktop.nix
    # zen-browser 基于 firefox，不仅使用自己的 .zen 目录，也使用 .mozilla
    ../common/optional/preservation/curious/zen.nix
    ../common/optional/preservation/curious/firefox.nix
    ../common/optional/preservation/curious/thunderbird.nix
    ../common/optional/boot/plymouth.nix
    ../common/optional/fonts.nix
    ../common/optional/desktop/discrete/dms.nix
    ../common/optional/desktop/discrete/niri.nix
    ../common/optional/desktop/discrete/cursors.nix
    ../common/optional/input-method.nix
    ../common/optional/daed.nix
    ../common/optional/nix/substituters/garnix.nix
    ../common/optional/preservation/daed.nix
    ../common/optional/steam.nix
    ../common/optional/vaultix/curious/rclone.nix
    ../common/optional/solaar.nix
    ../common/optional/openrazer.nix
    ../common/optional/users/users/curious/openrazer.nix

    ./boot.nix
    ./vaultix.nix
    ./networking.nix

    # hardware config
    ./hardware.nix
    # hardware config from community collection
    inputs.nixos-hardware.nixosModules.lenovo-legion-15arh05h
  ];

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
  system.stateVersion = "26.05"; # Did you read the comment?
}
