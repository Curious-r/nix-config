# 📦 Custom Packages

Custom packages are added to the repository's nixpkgs instance through the
`additions` overlay and are also exported through the Flake compatibility
boundary.

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
