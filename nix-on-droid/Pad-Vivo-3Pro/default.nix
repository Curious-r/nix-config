{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../common/core
    ../common/optional/nix/substituters/mainland.nix
  ];
  # Simply install the packages.
  environment.packages = [
    # User-facing stuff that you really want to have.

    # Some common stuff that people expect to have.
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

  # Read the changelog before changing this value.
  system.stateVersion = "24.05";
}
