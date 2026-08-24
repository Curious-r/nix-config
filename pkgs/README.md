# 📦 Custom Packages

Custom packages are added to every nixpkgs instance that imports this
repository's overlays through the `additions` overlay.

## Adding a Package

```nix
# pkgs/default.nix
pkgs:
{
  my-tool = pkgs.callPackage ./my-tool { };
}
```

## Building or Running

```console
nix run .#cc-switch
```

The Flake command uses the optional compatibility boundary; NixOS and Home
Manager modules consume the same package through the overlay.
