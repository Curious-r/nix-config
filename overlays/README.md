# Overlays

Overlays applied to the repository's main nixpkgs instance and exported through
the Flake compatibility boundary.

## Available Overlays

- `additions`: Brings custom packages from the `pkgs` directory into `pkgs`
- `modifications`: Placeholder for overriding existing packages

## Importing an Overlay

Apply every overlay from a traditional Nix evaluation:

```nix
nixpkgs.overlays = builtins.attrValues (import ./overlays);
```

Or select one through the Flake compatibility boundary:

```nix
{ self, ... }:
{
  nixpkgs.overlays = [
    self.overlays.<overlay-name>
  ];
}
```
