# Custom Modules

Reusable modules imported directly by this repository.

## Using Modules

Import these sets from their source paths:

```nix
nixosModules = import ./modules/nixos;
homeManagerModules = import ./modules/home-manager;
```

The optional Flake boundary exports the same sets as `nixosModules` and
`homeManagerModules`.

## Available Modules

- `homeManagerModules`: an empty set reserved for reusable Home Manager modules.
- `nixosModules`: self-contained NixOS modules, currently including `daed` and `ddns-go`.
