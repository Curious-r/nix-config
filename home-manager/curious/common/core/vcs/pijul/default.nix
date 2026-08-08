{ pkgs, ... }:
{
  home.packages = [ pkgs.pijul ];
  xdg.configFile = {
    "pijul/config.toml".source = ./config.toml;
    "pijul/identities/default/identity.toml".source = ./default/identity.toml;
  };
}
