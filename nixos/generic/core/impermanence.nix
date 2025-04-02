{ lib, inputs, ... }:
{
  imports = [
    inputs.impermanence.nixosModules.impermanence
    inputs.disko.nixosModules.disko
  ];
  # 配合 nixos-anywhere 部署时，在 stage1 阶段生成持久化目录所需的选项
  # 启用 initrd systemd 也是配合 rollback 服务的需要
  boot.loader.efi.canTouchEfiVariables = lib.mkForce true;
  boot.initrd.systemd.enable = lib.mkForce true;

  # /persistent 是你实际保存文件的地方
  environment.persistence."/persistent" = {
    # 不让这些映射的 mount 出现在文件管理器的侧边栏中
    hideMounts = true;

    # 你要映射的文件夹
    directories = [
      "/root"
      "/var"
    ];

    # 你要映射的文件
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
    ];

    # 类似的，你还可以在用户的 home 目录中单独映射文件和文件夹
    users.curious = {
      directories = [
        "nix-config"

        # 配置文件夹
        ".cache"
        ".config"
        ".local"
        ".ssh"
      ];
      files = [
        ".gitconfig"
      ];
    };
  };
}
