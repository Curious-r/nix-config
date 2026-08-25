# 🖥️ NixOS Configurations

NixOS system configurations for each host.

## Structure

- `common/`: Shared across all hosts
  - `core/`: Included by every host
  - `optional/`: Optional feature modules
- `Laptop-Legion-R7000`: Main laptop
- `Server-IdeaPad-G480`: Home server
- `Router-RaspberryPi-4B-1`: Raspberry Pi 4B router

## Deployment

Rebuild and switch from the traditional entrypoint:

```bash
nixos-rebuild switch --file nixos/default.nix --attr '<hostname>' --elevate run0
```

To build without applying, use the same entrypoint with the `build` action:

```bash
nixos-rebuild build --file nixos/default.nix --attr '<hostname>'
```

Or use the Flake compatibility boundary:

```bash
nixos-rebuild switch --flake .#<hostname> --elevate run0
```

CI builds the toplevel for each host and pushes it to `curious.cachix.org`, so local rebuilds pull it directly.
