{ inputs, pkgs, ... }:
{
  imports = [ inputs.pam-fido-remote.nixosModules.default ];

  security = {
    pam = {
      sshAgentAuth.enable = true;

      # 开启 PAM U2F 模块
      u2f = {
        enable = true;
        control = "sufficient"; # U2F 验证成功即可直接放行，无需再输入系统密码
        settings = {
          # 这里不用 interactive, 因为与 `nixos-rebuild boot --elevate run0 --ask-elevate-passowrd`
          # 中使用的 polkit-stdin-agent 不兼容，查看：https://codeberg.org/r-vdp/polkit-stdin-agent/issues/23
          cue = true;

          authfile = ./u2f_keys_local;
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

      # 为本机提供远程 fido 支持，功能来自 pam-fido-remote
      fido-remote = {
        enable = true;
        services = [
          "polkit-1"
        ];

        # 必须与 fido-remote-agent 的 rpIdAllow 绝对匹配
        rpId = "pam://gen1.remote.curious.host";

        # 与本地 u2f 一致的 Nix Store 路径写法
        # 我认为对于公钥来说扔在只读的 Nix Store 下就足够安全了，甚至我的配置都是公开的
        #
        # 需要使用字符串插值形式在评估时展开 path 类型的值，因为上游模块这里使用的类型（模
        # 块检查器层面）不是 lib.types.path 而是 lib.types.str
        authFile = "${./u2f_keys_remote}";

        # 因为绕过了 credentials 的自动推导逻辑，
        # 这里必须显式声明 users，以便系统通过 tmpfiles 预先创建 Socket 目录
        users = [ "curious" ];
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

    # 开启 fido-remote-agent 服务，在有远程鉴权需求时接管 fido 密钥
    fido-remote-agent = {
      enable = true;
      rpIdAllow = [ "pam://gen1.remote.curious.host" ];
    };
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
