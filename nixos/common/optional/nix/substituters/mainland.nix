{ ... }:
{
  nix.settings.substituters = [
    # Cache mirror located in mainland China.
    # Webstie: https://mirrors.cernet.edu.cn/
    "https://mirrors.cernet.edu.cn/nix-channels/store?priority=10"
  ];
}
