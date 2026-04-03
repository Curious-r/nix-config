{ ... }:
{
  # ==========================================
  # 默认通用密钥对
  # ==========================================

  # 个人私钥
  vaultix.secrets."ssh-key" = {
    file = ../../../../../secrets/nixos/common/optional/curious/ssh/id_ed25519.age;
    path = "/home/curious/.ssh/id_ed25519";
    owner = "curious";
    group = "users";
    mode = "0600";
  };

  # 个人公钥 (公钥非机密，直接作为模板明文写入)
  vaultix.templates."ssh-pub" = {
    name = "id_ed25519.pub";
    path = "/home/curious/.ssh/id_ed25519.pub";
    owner = "curious";
    group = "users";
    mode = "0644"; # 公钥权限要求较宽，通常为 644

    content = ''
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvTmb1zsdEywosctFd+5dlXM3fgKIeK5xzCZp0WtR1b curious
    '';
    trim = true;
  };

  # ==========================================
  # GitHub 专用密钥对
  # ==========================================

  # GitHub 专用私钥
  vaultix.secrets."github-ssh-key" = {
    file = ../../../../../secrets/nixos/common/optional/curious/ssh/id_ed25519_github.age;
    path = "/home/curious/.ssh/id_ed25519_github";
    owner = "curious";
    group = "users";
    mode = "0600";
  };

  # ==========================================
  # SSH 客户端配置
  # ==========================================

  # 部署 SSH 客户端配置
  vaultix.templates."ssh-config" = {
    name = "config";
    path = "/home/curious/.ssh/config";
    owner = "curious";
    group = "users";
    mode = "0600";

    content = ''
      # GitHub 专用配置
      Host github.com
        HostName github.com
        User git
        IdentityFile /home/curious/.ssh/id_ed25519_github
        ServerAliveInterval 60

      # 默认全局配置 ：显式指定默认使用通用私钥
      Host *
        IdentityFile /home/curious/.ssh/id_ed25519
    '';
    trim = true;
  };
}
