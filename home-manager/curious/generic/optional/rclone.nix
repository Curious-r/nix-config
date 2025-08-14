{ pkgs, config, ... }:
{
  systemd.user = {
    services.curious-drive-mounts = {
      Unit = {
        Description = "Curious drive mount unit";
        After = [ "network-online.target" ];
      };
      Service = {
        Type = "notify";
        ExecStart = "${pkgs.rclone}/bin/rclone --config=%h/.config/rclone/rclone.conf --vfs-cache-mode writes --ignore-checksum mount \"curious-drive:\" \"rclone\"";
        ExecStop = "/usr/bin/env fusermount3 -u %h/rclone";
      };
      Install.WantedBy = [ "default.target" ];
    };
    tmpfiles.rules = [ "d ${config.home.homeDirectory}/rclone 0755 ${config.home.username} users -" ];
  };
}
