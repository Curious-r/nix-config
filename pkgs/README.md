# 📦 Custom Packages

`pkgs/` is a scaffold for packaging tools that are not in nixpkgs yet.

It is currently empty: `aerion` has been merged into nixpkgs upstream, and its packages are kept here as commented-out examples.

## Adding a Package

```nix
# pkgs/default.nix
pkgs:
{
  my-tool = pkgs.callPackage ./my-tool { };
}
```

## Using Packages from This Flake

```nix
inputs.curious-r.packages.${pkgs.system}.my-tool
```

Or directly:

```bash
nix run "github:Curious-r/nix-config#my-tool"
nix shell "github:Curious-r/nix-config#my-tool"
```
