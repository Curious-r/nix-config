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

Build without applying from the traditional entrypoint:

```bash
nix build -f system.nix '<hostname>.config.system.build.toplevel'
```

Apply the built toplevel:

```bash
sudo ./result/bin/switch-to-configuration switch
```

Or use the Flake compatibility boundary:

```bash
sudo nixos-rebuild switch --flake .#<hostname>
```

CI builds the toplevel for each host and pushes it to `curious.cachix.org`, so local rebuilds pull it directly.
