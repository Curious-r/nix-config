{ pkgs, ... }:
{
  home.packages = [ pkgs.pijul ];
  xdg.configFile."pijul/config.toml".source = ./config.toml;
}
