{
  config,
  ...
}:
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

    # Alternative to `assets`, a directory containing the geo database.
    # assetsPath = "/etc/dae";
  };

  # 为了即时更新订阅，定时重载。
  systemd = {
    services."dae-reload" = {
      script = ''
        ${config.services.dae.package}/bin/dae reload
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        # RemainAfterExit = true; # 对于一次性任务并非必需，但可以保持状态
      };
    };
    timers."dae-reload" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m"; # 开机 5 分钟后首次运行
        OnUnitActiveSec = "12h"; # 之后每 12 小时运行一次
        Unit = "dae-reload.service";
      };
    };
  };
}
