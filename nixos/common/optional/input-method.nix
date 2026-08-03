{ pkgs, ... }:
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";

    fcitx5.waylandFrontend = true;

    fcitx5.addons = [
      pkgs.fcitx5-material-color # a color theme
      (pkgs.fcitx5-rime.override {
        rimeDataPkgs = [ pkgs.rime-wanxiang ];
      })
    ];

    fcitx5.settings = {
      globalOptions = {
        "Hotkey/AltTriggerKeys" = {
          "0" = ""; # 将替代触发键置为空字符串，从而禁用 Shift 切换逻辑
        };
        # 确保万无一失，把主触发键固定为 Ctrl+Space
        "Hotkey/TriggerKeys" = {
          "0" = "Control+space";
        };
      };

      # 顺便锁定输入法列表，防止重装后出现英文键盘
      inputMethod = {
        "Groups/0" = {
          Name = "Default";
          "Default Layout" = "us";
          DefaultIM = "rime";
        };

        "Groups/0/Items/0" = {
          Name = "rime";
          Layout = "";
        };
      };
    };
  };
}
