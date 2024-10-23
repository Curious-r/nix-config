{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  # Simply install just the packages
  environment.packages = with pkgs; [
    # User-facing stuff that you really really want to have
    git
    inputs.helix.packages."${pkgs.system}".helix # or some other editor, e.g. nano or neovim
    openssh
    curl

    # Some common stuff that people expect to have
    #diffutils
    #findutils
    #utillinux
    #tzdata
    #hostname
    #man
    #gnugrep
    #gnupg
    #gnused
    #gnutar
    #bzip2
    #gzip
    #xz
    #zip
    #unzip
  ];

  # Backup etc files instead of failing to activate generation if a file already exists in /etc
  environment.etcBackupExtension = ".bak";

  # Read the changelog before changing this value
  system.stateVersion = "24.05";

  # Set your time zone
  time.timeZone = "Asia/Shanghai";
}
