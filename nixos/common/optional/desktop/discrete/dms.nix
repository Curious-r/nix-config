{ config, lib, ... }:
let
  # 支持的 compositor 及启用条件
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

  # 获取首个启用的 compositor（无启用时返回 {name="none"}）
  enabledCompositor = lib.findFirst (opt: opt.condition) { name = "none"; } compositorOptions;
  cpt = enabledCompositor.name;

  # 各 compositor 对应的 greeter 配置
  compositorConfigs = {
    niri = "";
    hyprland = "";
    sway = "";
  };

  # 使用 attrByPath
  cptCfg = lib.attrByPath [ cpt ] "" compositorConfigs;
in
{
  programs.dms-shell.enable = true;
  services.displayManager.dms-greeter = {
    enable = true;
    compositor = {
      name = cpt;
      customConfig = cptCfg;
    };
    configHome = "/home/curious";
  };
}
