# Overlays

Overlays applied to nixpkgs in this flake.

## Available Overlays

- `additions`: Brings custom packages from the `pkgs` directory into `pkgs`
- `modifications`: Placeholder for overriding existing packages

## Importing an Overlay

```nix
{ self, ... }:
{
  nixpkgs.overlays = [
    self.overlays.<overlay-name>
  ];
}
```
