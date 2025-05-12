{ ... }:
{
  nix = {
    settings = {

      substituters = [
        # helix 官方 flake 的缓存源，如果 nixpkgs 版延迟太久了，或者上游又
        # 搞出热修复不改 tag 的操作，可以先用官方 flake 版本追新版本
        "https://helix.cachix.org"
      ];

      trusted-public-keys = [
        "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
      ];
    };
  };
}
