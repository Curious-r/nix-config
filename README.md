[![Declarative](https://img.shields.io/badge/Declarative-Configuration-success)](https://builtwithnix.org/)

# ❄️ Curious's Nix Config

My personal NixOS and Home Manager configurations, managed with Flakes.

## 🛠️ Tech Stack

- [Lix](https://git.lix.systems/lix-project/lix) - A delicious Nix fork
- [flake-parts](https://github.com/hercules-ci/flake-parts) - Simplify flake setup
- [vaultix](https://github.com/milieuim/vaultix) - Secret management
- [preservation](https://github.com/nix-community/preservation) - Opt-in state preservation
- [disko](https://github.com/nix-community/disko) - Declarative disk partitioning
- [treefmt-nix](https://github.com/numtide/treefmt-nix) - All-in-one formatter
- [devenv](https://github.com/cachix/devenv) - Developer environments

## 🏗️ Project Structure

- `nixos/`: NixOS system configurations
- `home-manager/`: Standalone Home Manager configurations
- `nix-on-droid/`: Nix-on-Droid configurations for Android
- `modules/`: Reusable Nix modules (NixOS, Home Manager, Flake Parts)
- `pkgs/`: Custom packages
- `overlays/`: Nixpkgs overlays
- `secrets/`: Encrypted secrets (managed by vaultix)

## 🖥️ Hosts

### NixOS

- `Laptop-Legion-R7000`: Main laptop
- `Server-IdeaPad-G480`: Home server
- `Router-RaspberryPi-4B-1`: Raspberry Pi 4B router

### Nix-on-Droid

- `Phone-Redmi-K50Pro`: Personal phone
- `Pad-Vivo-3Pro`: Tablet

---

[![Nix Flake](https://img.shields.io/badge/Nix-Flake-blue.svg?logo=NixOS&logoColor=white)](https://nixos.wiki/wiki/Flakes)
