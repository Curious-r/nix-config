# 🚀 Custom Packages Packaged by Me

### A Collection of Custom-Packaged Tools

These are the custom packages I've packaged for personal use.
Most packages are compatible with all systems specified in `flake.nix`. If a package is system-specific, this will be noted in its description.

---

### 🔨 Installing a Package

To use the packages, add the flake as an input in your configuration:

```bash
inputs = {
    curious-r.url = "github:Curious-r/nix-config";
    curious-r.inputs.nixpkgs.follows = "nixpkgs";
};
```

Once added, install the package using:

```bash
inputs.curious-r.packages.<package-name>
```

---

### ⚡ Quick Run

You can quickly run the package without installing it using:

```bash
nix run "ggithub:Curious-r/nix-config#<pkgname>"
```

Or bring the package into a shell environment with:

```bash
nix shell "github:Curious-r/nix-config#<pkgname>"
```

---
