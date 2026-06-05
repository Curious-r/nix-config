{ ... }:
{
  programs.mangohud = {
    enable = true;
    # enableSessionWide = true; # 如果想在桌面环境下全局默认加载（可能会干扰普通软件），可以设为 true。这里保持默认 false。

    settings = {
      # --- 性能限制与控制 ---
      fps_limit = [
        60
        90
        144
        0
      ]; # 设置多个帧率档位，0 代表无限制
      toggle_fps_limit = "F1"; # 在游戏中动态切换上述帧率档位的快捷键
      toggle_hud = "Shift_R+F12"; # 随时隐藏/显示监控面板的快捷键

      # --- 核心监控项显示 ---
      cpu_temp = true;
      cpu_stats = true;
      gpu_temp = true;
      gpu_stats = true;
      ram = true;
      vram = true;
      fps = true;
      frametime = true;

      # --- 外观与排版 ---
      legacy_layout = false; # 使用紧凑且现代的新版布局
      position = "top-left"; # HUD 显示在左上角
      round_corners = 10; # 面板圆角大小
      background_alpha = 0.5; # 面板背景透明度
    };
  };
}
