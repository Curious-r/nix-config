{
  config,
  lib,
  pkgs,
  primaryDiskWwid,
  backupRetentionPolicy,
  ...
}:
let
  cfg = config.boot.impermanence.btrfsSubvolume.rollback;
  primaryDiskUnit = "dev-disk-by\\x2did-${
    lib.replaceStrings [ "-" ] [ "\\x2d" ] primaryDiskWwid
  }.device";
in
{
  options = {
    boot.impermanence.btrfsSubvolume.rollback = {
      enable = lib.mkEnableOption "Service to rollback BTRFS @ subvolume to a pristine state";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.initrd.systemd.services.rollback = {
      description = "Rollback BTRFS @ subvolume to a pristine state";
      wantedBy = [ "initrd.target" ];
      requires = [ primaryDiskUnit ];
      after = [
        primaryDiskUnit
        # 如果使用了磁盘加密，请确保解密服务在此服务之前完成
      ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''

        echo "Starting rollback service..."

        # 创建挂载点目录
        mount_point="/.btrfs/main"
        mkdir -p "$mount_point"
        echo "Created mount point directory: $mount_point"

        # 挂载 Btrfs 分区
        mount -t btrfs -o subvol=/ "/dev/disk/by-id/${primaryDiskWwid}-part2" "$mount_point"
        echo "Mounted /dev/disk/by-id/${primaryDiskWwid}-part2 at $mount_point"

        # 检查是否存在指定的 Btrfs 子卷
        if [[ -d "$mount_point/@" ]]; then
          echo "Subvolume @ found. Proceeding with backup..."

          # 创建用于存储旧快照的目录
          mkdir -p "$mount_point/@.old"
          echo "Created backup directory: $mount_point/@.old"

          # 获取子卷的修改时间戳并格式化
          timestamp=$(date --date="@$(stat -c %Y "$mount_point/@")" "+%Y-%m-%d_%H:%M:%S")
          echo "Timestamp for current subvolume: $timestamp"

          # 移动当前子卷到旧备份目录
          mv "$mount_point/@" "$mount_point/@.old/$timestamp"
          echo "Moved current subvolume to backup directory: $mount_point/@.old/$timestamp"
        else
          echo "Subvolume @ not found. No action taken."
        fi

        # 定义递归删除 Btrfs 子卷的函数
        delete_subvolume_recursively() {
          IFS=$'\n'
          for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
              delete_subvolume_recursively "/btrfs_tmp/$i"
          done
          btrfs subvolume delete "$1"
        }

        # 删除超过${backupRetentionPolicy}天的旧备份
        for expired_backup in $(find "$mount_point/@.old" -mindepth 1 -maxdepth 1 -mtime +${backupRetentionPolicy}); do
          delete_subvolume_recursively "$expired_backup"
        done
        echo "Removed old backups older than 30 days"

        # 创建新的子卷
        btrfs subvolume create "$mount_point/@"
        echo "Created new subvolume: $mount_point/@"

        # 卸载挂载点
        umount "$mount_point"
        echo "Unmounted $mount_point"
      '';
    };
  };
}
