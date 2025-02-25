{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ../generic/core/default.nix
    ../generic/optional/nix/substituters/mainland.nix
  ];
  # Simply install just the packages
  environment.packages = with pkgs; [
    # User-facing stuff that you really really want to have
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

  # Read the changelog before changing this value
  system.stateVersion = "24.05";
}
