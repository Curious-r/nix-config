{ ... }:
{
  home.file.".local/share/fcitx5/rime" = {
    source = ./custom;
    recursive = true;
    force = true;
  };
  i18n.inputMethod.fcitx5.settings.globalOptions = {
    "Hotkey/AltTriggerKeys" = {
      "0" = ""; # 将替代触发键置为空字符串，从而禁用 Shift 切换逻辑
    };
    # 如果想确保万无一失，也可以把主触发键固定为 Ctrl+Space
    "Hotkey/TriggerKeys" = {
      "0" = "Control+space";
    };
  };

  # 顺便锁定输入法列表，防止重装后出现英文键盘
  i18n.inputMethod.fcitx5.settings.inputMethod = {
    "Groups/0" = {
      Name = "Default";
      "Default Layout" = "us";
      Items = [ { Name = "rime"; } ];
    };
  };
}
