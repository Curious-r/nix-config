{ pkgs, ... }:
{
  services = {
    gnome.gnome-keyring.enable = false;
    oo7.enable = true;
  };

  # 用于认证弹窗
  environment.systemPackages = [ pkgs.gcr ];
  services.dbus.packages = [ pkgs.gcr ];

  # 开启一些基础的规则钩子，等 #544377 合并之后估计会重复，到时候删除
  security.pam.services = {
    passwd.oo7.enable = true;
  };

  systemd.user.services.oo7-daemon.serviceConfig = {
    # 上游包 pkgs.oo7-server 提供的 .service 文件中，ExecStart 指向的是
    # Nix Store 里的原始路径（/nix/store/.../libexec/oo7-daemon），而不是
    # Wrapper 路径（/run/wrappers/bin/oo7-daemon）
    #
    # 但 Systemd User Services（用户级服务）在启动进程时，无法继承赋予给可执行
    # 文件的 Capabilities (提权能力)
    #
    # 导致无法使用使用 mlock 系统调用将这块内存锁在物理内存中，因此暂时允许该服务
    # 锁定最多 8MB 的物理内存
    #
    # 预计也会在 #544377 中修复，虽然目前来看还没有实际改动，可能被上游阻塞
    LimitMEMLOCK = "8388608";
  };
}
