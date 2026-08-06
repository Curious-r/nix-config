{ pkgs, lib, ... }:
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

  # 有些模块如 niri 硬编码了 portal.Secret，我们在此覆盖它
  xdg.portal.config.niri."org.freedesktop.impl.portal.Secret" = lib.mkForce "oo7-portal";
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

  # NOTE:
  # 针对 u2f 登录时不能通过密码自动解锁钥匙环的情况，暂时使用 systemd-creds 来加密存储密码，这样在用户登录后密码自
  # 动在内存中解密，用户无感
  # 参考：https://github.com/linux-credentials/oo7/commit/8891a9cc09d0ed502800e1910ad6e880f1bbbae9
  #
  # 必要工作：
  # ```bash
  # echo -n "mypasswd" | systemd-creds encrypt \
  #   --user \
  #   --tpm2-pcrs=0+7 \
  #   --name=oo7.keyring-encryption-password \
  #   - ~/.config/credstore.encrypted/oo7.keyring-encryption-password
  # ```
  # 注意，此凭据的正确加密、解密，有众多因子参与，包括主机密钥（/var/lib/systemd/credential.secret）、
  # machine-id、用户名、UID、TPM，因此如果使用了不可变系统相关技术，要注意处理相应状态的持久化，一旦其中
  # 有因子发生变化，现有凭据就会解密失败
  #
  # 尤其是主机密钥，systemd-creds 不接受符号链接，文件权限严格要求为 0400，这在绑定挂载时也要注意
  # 另外，由于 systemd-creds setup 使用原子替换来生成 /var/lib/systemd/credential.secret，在绑定
  # 挂载的情况下也是无法正常生成的，在新装机时，我们需要在持久化目录中手工创建好这个文件，借助挂载命名空间创建
  # 隔离环境：
  # ```
  # run0 unshare -m bash -c '
  #   # 创建一个基于内存的可写临时目录，并对齐原始目录的权限
  #   mkdir -p /tmp/fake-systemd-dir
  #   chmod --reference=/var/lib/systemd /tmp/fake-systemd-dir
  #   chown --reference=/var/lib/systemd /tmp/fake-systemd-dir

  #   # 挂载覆盖，让 /var/lib/systemd 在当前隔离环境中可写
  #   # （因为处于 unshare -m 下，这完全不会干扰正在运行的主系统服务）
  #   mount --bind /tmp/fake-systemd-dir /var/lib/systemd

  #   # 正常生成密钥
  #   systemd-creds setup

  #   # 将生成的凭据安全拷贝到你的持久化存储目录中
  #   # ！！！目标路径需要替换为实际存放 credential.secret 的位置！！！
  #   cp /var/lib/systemd/credential.secret /persistent/var/lib/systemd/credential.secret

  #   echo "密钥生成并提取成功！"
  # '
  # ```
  # 完成后重启，即可使 preservation 挂载到正确的文件
  #
  # 或许日后会有更好的方法集成 u2f，但目前这样也能接受
}
