{ ... }:
{
  environment.persistence."/persistent" = {
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
