{ lib, ... }:
{
  # Enable docker.
  virtualisation.docker = {
    enable = true;
    # btrfs 存储驱动在系统软重启时的解挂载处理似乎有问题，可能会引起我的 impermance btrfs 根目录回滚失败，
    # 这里尝试使用 overlay2
    storageDriver = lib.mkDefault "overlay2";
  };
}
