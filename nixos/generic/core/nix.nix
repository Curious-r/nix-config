{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
{
  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    settings = {
      # See https://jackson.dev/post/nix-reasonable-defaults/
      connect-timeout = 5;
      log-lines = 25;
      min-free = 128000000; # 128MB
      max-free = 1000000000; # 1GB

      # Deduplicate and optimize nix store
      auto-optimise-store = true;

      experimental-features = [
        "nix-command"
        "flakes"
      ];
      warn-dirty = false;

      # given the users in this list the right to specify additional substituters via:
      #    1. `nixConfig.substituers` in `flake.nix`
      #    2. command line args `--options substituers http://xxx`
      trusted-users = [ "curious" ];
      substituters = [
        "https://cache.nixos.org"
      ];
      trusted-public-keys = [
        # the default public key of cache.nixos.org, it's built-in, no need to add it here
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      ];
    };

    # Garbage Collection
    gc = {
      automatic = true;
      options = "--delete-older-than 10d";
    };
  };
}
