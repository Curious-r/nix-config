# 🚀 Overlays

My set of overlays for packages to be applied on different set of configurations.

### 🔨 Available Overlays

- `additions`: Brings custom packages from the `pkgs` directory into `pkgs`.
- `modifications`: (Empty placeholder) For overriding existing packages.
- `stable-packages`: Exposes a `stable` attribute in `pkgs` pointing to the stable nixpkgs input.

### 🔨 Import the overlay on the config

```nix
{ self, ... }:
{
  nixpkgs.overlays = [
    self.overlays.<overlay-name>
  ];
}
```
