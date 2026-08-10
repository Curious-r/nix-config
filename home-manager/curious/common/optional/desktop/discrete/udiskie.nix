{ ... }:
{
  services.udiskie = {
    enable = true;
    automount = true; # 自动挂载插入的设备
    notify = true; # 发送桌面通知
    tray = "auto"; # 在系统托盘中生成弹出图标
    settings = {
      device_config = [
        # 虚拟 loop 设备不必自动挂载。
        {
          device_file = "/dev/loop*";
          automount = false;
        }

        # vfat（FAT32）格式的 U 盘，强制不许执行程序。
        {
          id_type = "vfat";
          options = [
            "noexec"
          ];
        }

        # 可以通过 ID 筛选为单一设备实施策略：
        # 通过 UUID 匹配
        {
          id_uuid = "1234abcd-56ef-78gh-90ij-klmnopqrstuv";
          ignore = true;
        }
        # UUID 会在重新分区后变化，如果需要更稳定地追踪，可以用 symlinks
        # 代替 id_uuid，匹配指定 WWID 的硬件：
        {
          symlinks = "/dev/disk/by-id/ata-My_Custom_Backup_Disk_S3Z8NB0K123456X";
          automount = false;
        }
      ];
    };
  };
}
