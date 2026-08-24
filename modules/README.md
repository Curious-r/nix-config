# Custom Modules

Reusable modules exported by this repository's Flake compatibility layer.

## Using Modules

The Flake compatibility layer exposes these sets directly:

```nix
nixosModules = import ./nixos;
homeManagerModules = import ./home-manager;
```

## Available Modules

- `homeManagerModules`: an empty set reserved for reusable Home Manager modules.
- `nixosModules`: self-contained NixOS modules, currently including `daed` and `ddns-go`.
