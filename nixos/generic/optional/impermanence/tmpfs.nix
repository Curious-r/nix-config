{ ... }:
{
  imports = [ ../disko/primary/tmpfs-efi-btrfs-swap.nix ];
  systemd.services.nix-daemon = {
    environment = {
      # 指定临时文件的位置
      TMPDIR = "/var/cache/nix";
    };
    serviceConfig = {
      # 在 Nix Daemon 启动时自动创建 /var/cache/nix
      CacheDirectory = "nix";
    };
  };
  environment.variables.NIX_REMOTE = "daemon";
}
