{ config, lib, ... }:
let
  # 定义所有支持的 compositor 选项及其启用条件
  compositorOptions = [
    {
      name = "niri";
      condition = config.programs.niri.enable or false;
    }
    {
      name = "hyprland";
      condition = config.programs.hyprland.enable or false;
    }
    {
      name = "sway";
      condition = config.programs.sway.enable or false;
    }
  ];

  # 找到第一个启用的 compositor
  enabledCompositor =
    lib.findFirst (opt: opt.condition) { name = "none"; } # 默认值，当没有支持的 compositor 启用时使用，用于提供报错信息
      compositorOptions;

  cpt = enabledCompositor.name;
in
{
  programs.dms-shell.enable = true;
  services.displayManager.dms-greeter = {
    enable = true;
    compositor.name = cpt;
  };
}
