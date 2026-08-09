{ pkgs, lib, ... }:
{
  services = {
    gnome.gnome-keyring.enable = false;
    oo7.enable = true;
  };

  # oo7 启动时会用 mlockall 尝试锁住全部内存，失败只打一条 WARN 后继续运行
  # （密钥材料可能被换出到磁盘）。实测（kernel 7.1.6 + systemd user manager）：
  # 本内核的 mlock 只认初始用户命名空间里的 CAP_IPC_LOCK，RLIMIT_MEMLOCK 不再
  # 对无特权进程生效；而 systemd 用户服务的沙箱选项（PrivateTmp/ProtectSystem/
  # PrivateNetwork/PrivateDevices/...）都会通过私有 userns 实现，能力被关在子
  # 命名空间里，无法满足该检查。因此上游 unit 自带沙箱时 mlock 必然失败，我们
  # 保留上游原样并接受这条警告；覆盖 NoNewPrivileges/PrivateUsers 或加大
  # LimitMEMLOCK 均无效。

  # 用于认证弹窗
  environment.systemPackages = [ pkgs.gcr ];
  services.dbus.packages = [ pkgs.gcr ];

  # 开启一些基础的规则钩子，等 #544377 合并之后估计会重复，到时候删除
  security.pam.services = {
    passwd.oo7.enable = true;
  };

  # 有些模块如 niri 硬编码了 portal.Secret，我们在此覆盖它
  xdg.portal.config.niri."org.freedesktop.impl.portal.Secret" = lib.mkForce "oo7-portal";

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
  # 另外，由于 systemd-creds setup 使用原子更新来生成 /var/lib/systemd/credential.secret，在绑定
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
