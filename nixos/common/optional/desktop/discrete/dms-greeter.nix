{
  config,
  lib,
  ...
}:
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
    niri = ''
      hotkey-overlay {
          skip-at-startup
      }

      environment {
          DMS_RUN_GREETER "1"
      }

      gestures {
        hot-corners {
          off
        }
      }

      layout {
        background-color "#000000"
      }
    '';
    hyprland = ''
      env = DMS_RUN_GREETER,1

      misc {
          disable_hyprland_logo = true
      }
    '';
    sway = ''
      # Sway greeter configuration
      # The exec command to launch the greeter is automatically appended by dms-greeter
    '';
  };

  # 使用 attrByPath
  cptCfg = lib.attrByPath [ cpt ] "" compositorConfigs;
in
{
  services.displayManager.dms-greeter = {
    enable = true;
    compositor = {
      name = cpt;
      customConfig = cptCfg;
    };
    configHome = "/home/curious";
  };
}
