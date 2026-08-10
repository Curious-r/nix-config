{ pkgs, lib, ... }:
{
  nix = {
    package = lib.mkDefault pkgs.lixPackageSets.stable.lix;
    settings = {

      substituters = [
        # 默认缓存源，Home Manager 似乎需要显式配置这个。
        "https://cache.nixos.org"
        # nix community's cache server
        "https://nix-community.cachix.org"
        # 自己的 Cachix 缓存：CI 构建产物
        "https://curious.cachix.org"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        # nix community's cache server
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        # 自己的 Cachix 缓存
        "curious.cachix.org-1:5dkD/spZ5UAuL9K84Fy2xCdtfey1TAWj2RKUu2sjy3E="
      ];
    };
  };
}
