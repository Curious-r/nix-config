{ pkgs, inputs, ... }:
{
  programs.yazi = {
    enable = true;
    package = inputs.yazi.packages.${pkgs.stdenv.hostPlatform.system}.default; # if you use overlays, you can omit this
  };
}
