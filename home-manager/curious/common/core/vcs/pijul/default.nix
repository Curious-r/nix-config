{ pkgs, ... }:
{
  home.packages = with pkgs; [ pijul ];
  xdg.configFile."pijul/config.toml".source = ./config.toml;
}
