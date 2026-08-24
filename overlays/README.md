# Overlays

Overlays applied to the repository's main nixpkgs instance.

## Available Overlays

- `additions`: Brings custom packages from the `pkgs` directory into `pkgs`
- `modifications`: Placeholder for overriding existing packages

## Importing an Overlay

Apply every overlay from a traditional Nix evaluation:

```nix
nixpkgs.overlays = builtins.attrValues (import ./overlays);
```

The optional Flake boundary also exports each overlay by name:

```nix
{ self, ... }:
{
  nixpkgs.overlays = [
    self.overlays.<overlay-name>
  ];
}
```
