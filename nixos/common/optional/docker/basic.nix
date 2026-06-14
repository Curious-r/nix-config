{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Enable docker.
  virtualisation.docker = {
    enable = true;
    storageDriver = lib.mkDefault "overlay2";
    extraPackages = lib.mkIf config.networking.nftables.enable [ pkgs.nftables ];
    daemon.settings = lib.mkIf config.networking.nftables.enable {
      "firewall-backend" = "nftables";
    };
  };
}
