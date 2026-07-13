{ ... }:
{
  services.ncps = {
    enable = true;
    cache = {
      hostName = "Server-IdeaPad-G480";
      maxSize = "50G";
      lru.schedule = "0 2 * * *";
      allowPutVerb = true;
      allowDeleteVerb = true;
      upstream = {
        urls = [
          "https://cache.nixos.org"
          "https://mirrors.sjtug.sjtu.edu.cn/nix-channels/store"
          "https://nix-community.cachix.org"
        ];
        publicKeys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };
    };
  };
}
