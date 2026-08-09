{ config, ... }:
{
  services.dae = {
    enable = true;

    openFirewall = {
      enable = true;
      port = 12345;
    };
    configFile = config.vaultix.secrets."config.dae".path;
    /*
      default options

      package = pkgs.dae;
      disableTxChecksumIpGeneric = false;
      assets = [ pkgs.v2ray-geoip pkgs.v2ray-domain-list-community ];
    */

    # alternative of `assets`, a dir contains geo database.
    # assetsPath = "/etc/dae";
  };
}
