{
  self,
  config,
  pkgs,
  ...
}:
{
  imports = [ self.nixosModules.ddns-go ];

  services.ddns-go = {
    enable = true;
    configFile = config.vaultix.secrets."ddns-go.yaml".path;
  };

  # 以下环境追加用于 ddns-go 的脚本模式
  # 网卡 + 正则无法规避宽带重拨造成的活跃地址和弃用地址混在一起的问题
  systemd.services.ddns-go = {
    # 确保 ddns-go 服务能找到脚本中用到的所有命令
    path = with pkgs; [
      bash # 为 sh -c 提供运行时
      iproute2 # 提供 ip 命令
      gawk # 提供 awk
      gnugrep # 提供 grep
      coreutils # 提供 cut 和 head
    ];
  };
}
