{ pkgs, ... }:
{
  programs = {
    gamescope = {
      enable = true;
    };
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      gamescopeSession.enable = true;
      extraPackages = [ pkgs.hidapi ];
    };
    gamemode.enable = true;
  };
}

# WAYLAND 多屏与 PROTON 游戏鼠标失效备忘：
# 当外接显示器断开或布局错乱，导致当前游戏屏幕在全局画布的逻辑坐标不为原点（如 position x=1920 y=0）时，
# Xwayland/Proton 游戏会因无法正确映射绝对坐标，导致“鼠标指针能动但点击完全失效/穿透”的 Bug。
#
# 快速修复方案：
# 打开 dms 显示设置，显示隐藏设备，将当前游戏屏幕拖到最左最上（确保 niri msg outputs 中 Logical position 为 0,0）。
# 或者使用 gamescope，但对于窗口游戏还是前一种方法合适。
