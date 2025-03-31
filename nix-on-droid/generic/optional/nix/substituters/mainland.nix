{ ... }:
{
  nix = {
    substituters = [
      # cache mirror located in Chinese mainland
      # status: https://mirror.sjtu.edu.cn/
      "https://mirror.sjtug.sjtu.edu.cn/nix-channels/store"
      # status: https://mirrors.ustc.edu.cn/status/
      # "https://mirrors.ustc.edu.cn/nix-channels/store"
    ];
  };
}
