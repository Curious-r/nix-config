{ config, ... }:

{
  vaultix.secrets = {
    # 这里的 ID 是 "rclone-user"
    "rclone-user" = {
      file = ../../../../../secrets/nixos/common/optional/curious/rclone-user.age;
    };
    "rclone-pass" = {
      file = ../../../../../secrets/nixos/common/optional/curious/rclone-pass.age;
    };
  };

  vaultix.templates = {
    "rclone-config" = {
      name = "rclone.conf";
      path = "/home/curious/.config/rclone/rclone.conf";
      owner = "curious";
      group = "users";
      mode = "0600"; # 包含密码的文件，严格建议 600

      # 直接在 Nix 里维护配置结构
      content = ''
        [curious-drive]
        type = webdav
        url = https://drive.curious.host/dav
        vendor = other
        user = ${config.vaultix.placeholder.rclone-user}
        pass = ${config.vaultix.placeholder.rclone-pass}
      '';

      trim = true; # 确保注入密码时不会带上多余的换行符
    };
  };
}
