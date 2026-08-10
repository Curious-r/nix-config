{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
{
  nix = {
    # This will add each flake input as a registry.
    # To make nix3 commands consistent with your flake.
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will add your inputs to the system's legacy channels.
    # Making legacy nix commands consistent as well.
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    package = pkgs.lixPackageSets.stable.lix;

    settings = {
      # See https://jackson.dev/post/nix-reasonable-defaults/.
      connect-timeout = 5;
      log-lines = 25;
      min-free = 128000000; # 128MB
      max-free = 1000000000; # 1GB

      # Deduplicate and optimize the nix store.
      auto-optimise-store = true;

      experimental-features = [
        "nix-command"
        "flakes"
      ];

      use-xdg-base-directories = true;
      warn-dirty = false;

      # Give the users in this list the right to specify additional substituters via:
      #    1. `nixConfig.substituters` in `flake.nix`.
      #    2. Command-line args `--options substituters http://xxx`.
      trusted-users = [ "curious" ];
      substituters = [
        "https://cache.nixos.org"
        # Nix community's cache server
        "https://nix-community.cachix.org"
        # 自己的 Cachix 缓存：CI 构建产物
        "https://curious.cachix.org"
      ];
      trusted-public-keys = [
        # The default public key of cache.nixos.org is built in; no need to add it here.
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        # Nix community's cache server
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        # 自己的 Cachix 缓存
        "curious.cachix.org-1:5dkD/spZ5UAuL9K84Fy2xCdtfey1TAWj2RKUu2sjy3E="
      ];
    };

    # Garbage Collection
    gc = {
      automatic = true;
      options = "--delete-older-than 10d";
    };
  };
}
