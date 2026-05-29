# 🖥️ NixOS Configurations

This directory contains the NixOS system configurations for various hosts.

## 📁 Structure

- `common/`: Shared configurations across all hosts.
    - `core/`: Critical configurations included by every host.
    - `optional/`: Optional feature modules.
- `Laptop-Legion-R7000`: Main workstation.
- `Server-Ideapad-G480`: Home server.
- `Router-RaspberryPi-4B-1`: Raspberry Pi 4B acting as a router.

## 🚀 Deployment

To apply a configuration to the local system:

```bash
sudo nixos-rebuild switch --flake .#<hostname>
```

To build a configuration without applying:

```bash
nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel
```
