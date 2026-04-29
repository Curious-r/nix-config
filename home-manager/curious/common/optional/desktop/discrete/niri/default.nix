{ pkgs, ... }:
{
  xdg.configFile."niri/config.kdl".source = ./config.kdl;
  home.packages = with pkgs; [
    xwayland-satellite
  ];

  # 有些命令行程序的 .desktop 文件中有 Terminal=true 的配置，DMS 的启动器会使用 $TERMINAL 环境变量来唤起终端
  # 上游有这个 issue，不知道后面会不会有什么别的方法解决
  # 既然我们在 niri 快捷键里都写死 Mod + T 唤起 ghostty 了，那我们暂时硬编码这个环境变量的配置也写在这里吧
  systemd.user.sessionVariables = {
    TERMINAL = "ghostty";
  };
}
