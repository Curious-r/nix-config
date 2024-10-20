{ enableRestoreService, outputs,  ... }:
{
  imports = [
    ../disko/primary/efi-btrfs.nix
    outputs.nixosModules.boot.impermanence.btrfsSubvolume
  ];
  # 系统完成启动后根目录 / 挂载于名为 @ 的子卷上，所谓回滚，即在启动阶段备份该子卷并重建空白的同名子卷
  # 下面的两个 option 分别创建了启动阶段的 systemd 服务，分别用于备份并回滚 @ 子卷和恢复备份的 @ 子卷
  # 日常使用时保持 restore 服务禁用，而恢复备份时则启用 restore 服务
  # 进行回滚需要传入要恢复的备份名称
  boot.impermanence.btrfsSubvolume.rollback.enable = true;
  boot.impermanence.btrfsSubvolume.restore.enable = enableRestoreService;
}
