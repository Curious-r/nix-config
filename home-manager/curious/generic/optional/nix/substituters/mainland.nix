{ ... }:
{
  nix = {
    settings = {

      substituters = [
        # cache mirror located in Chinese mainland
        # status: https://mirrors.sjtug.sjtu.edu.cn/
        "https://mirrors.sjtug.sjtu.edu.cn/nix-channels/store"
        # status: https://mirrors.ustc.edu.cn/status/
        # "https://mirrors.ustc.edu.cn/nix-channels/store"
      ];
    };
  };
}
