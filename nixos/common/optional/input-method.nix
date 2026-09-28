{ pkgs, ... }:
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";

    fcitx5.addons = [
      (pkgs.fcitx5-rime.override {
        rimeDataPkgs = [ pkgs.rime-wanxiang ];
      })
    ];

    # 注意：此处配置均写入 `/etc/xdg/fcitx5/`（系统级），且不同区块对应独立的物理文件。
    # Fcitx5 采用【文件遮蔽】而非【键值合并】的方式处理配置回退：一旦在 GUI
    # (fcitx5-configtool) 中点击 Apply/OK，就会在 `xdg.configFile."fcitx5/"` 下生成对应文件
    # （哪怕全为注释占位符），导致此处系统级配置区块被完全忽略。
    # 维护建议：日常避免在 GUI 点保存；若发现配置失效，直接清理用户目录下的对应文件即可。
    fcitx5.settings = {
      globalOptions = {
        "Hotkey/AltTriggerKeys" = {
          "0" = ""; # 将替代触发键置为空字符串，从而禁用 Shift 切换逻辑。
        };
        # 确保万无一失，把主触发键固定为 Ctrl+Space。
        "Hotkey/TriggerKeys" = {
          "0" = "Control+space";
        };
      };

      # 顺便锁定输入法列表，防止重装后出现英文键盘。
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

      # 禁用 Rime 预编辑光标固定在开头的行为，避免 PiliPlus、Steam 等软件光标乱飞。
      addons = {
        rime = {
          globalSection = {
            PreeditCursorPositionAtBeginning = "False";
          };
        };
      };
    };
  };
}
