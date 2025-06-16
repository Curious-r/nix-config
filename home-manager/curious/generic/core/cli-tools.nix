{ pkgs, inputs, ... }:

{

  programs.zellij.enable = true;
  programs.bottom.enable = true;
  programs.yazi = {
    enable = true;
    package = inputs.yazi.packages.${pkgs.system}.default; # if you use overlays, you can omit this
  };

}
