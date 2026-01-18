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

      package = inputs.daeuniverse.packages.x86_64-linux.dae;
      disableTxChecksumIpGeneric = false;
      assets = with pkgs; [ v2ray-geoip v2ray-domain-list-community ];
    */

    # alternative of `assets`, a dir contains geo database.
    # assetsPath = "/etc/dae";
  };
}
