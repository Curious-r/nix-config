{
  config,
  lib,
  ...
}:
let
  nixosRoot = ../../../..;
  dirEntries = builtins.readDir nixosRoot;
  isRemoteServer =
    name: type:
    type == "directory"
    && name != "common"
    && name != config.networking.hostName
    && builtins.pathExists (nixosRoot + "/${name}/default.nix");

  remoteServers = builtins.filter (name: isRemoteServer name dirEntries.${name}) (
    builtins.attrNames dirEntries
  );
in
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

  # 个人公钥（公钥非机密，直接作为模板明文写入）。
  vaultix.templates."ssh-pub" = {
    name = "id_ed25519.pub";
    path = "/home/curious/.ssh/id_ed25519.pub";
    owner = "curious";
    group = "users";
    mode = "0644"; # 公钥权限要求较宽，通常为 644。

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

      # Nest 专用配置
      Host nest.pijul.com
        User curious
        IdentityFile ~/.ssh/id_ed25519_github

      # ==========================================
      # 集群受管服务器：定向注入 pam-fido-remote 隔离套接字
      # ==========================================
      ${lib.concatMapStrings (host: ''
        Match host ${host},${host}.*
          RemoteForward /run/fido-remote/%r/agent.sock ''${XDG_RUNTIME_DIR}/fido-remote/${host}.sock

      '') remoteServers}
      # 局域网私网 IP 直连兜底：转发至共享的 legacySocket，允许未通过主机名匹配的内网连接鉴权。
      Match host 192.168.*,10.*,172.16.*,172.17.*,172.18.*,172.19.*,172.2*,172.30.*,172.31.*,fd*,fe80:*
        RemoteForward /run/fido-remote/%r/agent.sock ''${XDG_RUNTIME_DIR}/fido-remote/agent.sock

      # 默认全局配置：显式指定默认使用通用私钥。
      Host *
        IdentityFile ''${HOME}/.ssh/id_ed25519
    '';
    trim = true;
  };
}
