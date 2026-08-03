{ pkgs, ... }:
{
  programs.nix-ld = {
    enable = true;
    libraries = [
      pkgs.stdenv.cc.cc.lib
      pkgs.zlib
      pkgs.openssl
      pkgs.curl
      pkgs.glibc
    ];
  };
}
