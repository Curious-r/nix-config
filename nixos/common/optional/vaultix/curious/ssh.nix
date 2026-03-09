{ ... }:
{
  # 部署 GitHub 私钥
  vaultix.secrets."github-ssh-key" = {
    file = ../../../../../secrets/nixos/common/optional/curious/ssh/ed25519-github.age;
    path = "/home/curious/.ssh/id_ed25519_github";
    owner = "curious";
    group = "users";
    mode = "0600";
  };

  # 部署 SSH 客户端配置
  vaultix.templates."ssh-config" = {
    name = "config";
    path = "/home/curious/.ssh/config";
    owner = "curious";
    group = "users";
    mode = "0600";

    content = ''
      Host github.com
        HostName github.com
        User git
        IdentityFile /home/curious/.ssh/id_ed25519_github
        ServerAliveInterval 60
    '';

    trim = true;
  };
}
