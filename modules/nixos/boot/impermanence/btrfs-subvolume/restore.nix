{
  config,
  lib,
  pkgs,
  primaryDiskWwid,
  restoreTarget,
  ...
}:
let
  cfg = config.boot.impermanence.btrfsSubvolume.restore;
  requiredUnit = "dev-disk-by\\x2did-${
    lib.replaceStrings [ "-" ] [ "\\x2d" ] primaryDiskWwid
  }\\x2dpart2.device";
in
{
  options = {
    boot.impermanence.btrfsSubvolume.restore = {
      enable = lib.mkEnableOption "Service to restore a specific BTRFS @ subvolume from backup";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.initrd.systemd.services.restore = {
      description = "Restore a specific BTRFS @ subvolume from backup";
      wantedBy = [ "initrd.target" ];
      requires = [ requiredUnit ];
      after = [ "rollback.service" ];
      before = [ "-.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''

        echo "Starting restore service..."
        # 创建挂载点目录
        mount_point="/.btrfs/main"
        mkdir -p "$mount_point"
        echo "Created mount point directory: $mount_point"

        # 挂载 Btrfs 分区
        mount "/dev/disk/by-id/${primaryDiskWwid}-part2" "$mount_point"
        echo "Mounted /dev/disk/by-id/${primaryDiskWwid}-part2 at $mount_point"

        # 检查备份是否存在
        if [[ -d "$mount_point/@.old/${restoreTarget}" ]]; then
          echo "Restoring backup: ${restoreTarget}"

          # 删除当前子卷
          btrfs subvolume delete "$mount_point/@"
          echo "Deleted current subvolume @"

          # 重命名备份子卷为 @
          mv "$mount_point/@.old/${restoreTarget}" "$mount_point/@"
          echo "Restored backup to subvolume @: $mount_point/@.old/${restoreTarget}"
        else
          echo "Backup ${restoreTarget} not found!"
        fi

        # 卸载挂载点
        umount "$mount_point"
        echo "Unmounted $mount_point"
      '';
    };
  };
}
