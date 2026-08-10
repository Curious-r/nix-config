{ ... }:
{
  nix.settings.substituters = [
    # Cache mirror located in mainland China.
    # Status: https://mirrors.tuna.tsinghua.edu.cn/
    "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
    # Status: https://mirrors.sjtug.sjtu.edu.cn/
    "https://mirrors.sjtug.sjtu.edu.cn/nix-channels/store"
    # Status: https://mirrors.ustc.edu.cn/status/
    # "https://mirrors.ustc.edu.cn/nix-channels/store"
  ];
}
