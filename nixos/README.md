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

Apply to the local system:

```bash
sudo nixos-rebuild switch --flake .#<hostname>
```

Build without applying:

```bash
nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel
```

CI builds the toplevel for each host and pushes it to `curious.cachix.org`, so local rebuilds pull it directly.
