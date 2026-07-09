{ pkgs, ... }:
{
  security = {
    pam = {
      sshAgentAuth.enable = true;

      # 开启 PAM U2F 模块
      u2f = {
        enable = true;
        control = "sufficient"; # U2F 验证成功即可直接放行，无需再输入系统密码
        settings = {
          interactive = true; # 强制进行交互验证（要求触摸硬件设备）
        };
      };

      # 将 U2F 策略注入特定服务
      services = {
        # 桌面登录管理器 (Wayland/Niri 鉴权)
        "dms-greeter".u2fAuth = true;
        # Polkit，接管 run0 的提权认证
        "polkit-1".u2fAuth = true;
        # 本地 TTY 终端登录
        login.u2fAuth = true;
      };
    };

    # 用 run0 了，sudo 系彻底掰掰
    sudo.enable = false;
  };

  services = {
    # 启用 PC/SC 守护进程用于 PIV (Age 加密)
    pcscd.enable = true;

    # 放行 FIDO2 (HID) 权限与依赖
    udev.packages = with pkgs; [
      libfido2
    ];
  };

  # 在 nixos-rebuild 中允许目标主机支持来自远程的 run0 提权激活
  # 这会自动启用 run0
  system.tools.nixos-rebuild.enableRun0Elevation = true;

  environment.systemPackages = with pkgs; [
    libfido2
    pam_u2f
    pcsc-tools
  ];
}
