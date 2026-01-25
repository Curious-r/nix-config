{
  pkgs,
  ...
}:
{
  environment.packages = with pkgs; [
    # 这里不像 nixos 一样用官方仓库 flake，因为他们的二进制
    # 缓存里不提供 linux-arm64 版本，手机编译起来太慢了
    helix # or some other editor, e.g. nano or neovim
    git
    openssh
    curl
  ];
}
