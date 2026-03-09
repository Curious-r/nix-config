{ ... }:
{
  #  部署 Git 全局配置
  vaultix.templates."git-config" = {
    name = ".gitconfig";
    path = "/home/curious/.gitconfig";
    owner = "curious";
    group = "users";
    mode = "0644"; # Git 配置文件给 644 即可

    content = ''
      [user]
      	name = Curious
      	email = Curious@curious.host

      [init]
      	defaultBranch = main

      [url "git@github.com:"]
       	insteadOf = https://github.com/
    '';

    trim = true;
  };
}
