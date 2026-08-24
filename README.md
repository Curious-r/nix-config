[![Declarative](https://img.shields.io/badge/Declarative-Configuration-success)](https://builtwithnix.org/)
[![CI](https://github.com/Curious-r/nix-config/actions/workflows/ci.yml/badge.svg)](https://github.com/Curious-r/nix-config/actions/workflows/ci.yml)

# ❄️ Curious's Nix Config

Personal NixOS, Home Manager and nix-on-droid configurations. The experimental
branch evaluates these targets directly with npins-pinned sources while keeping
the legacy Flake available during migration.

## Tech Stack

- [Lix](https://git.lix.systems/lix-project/lix) - A delicious Nix fork
- [flake-parts](https://github.com/hercules-ci/flake-parts) - Flake module system
- [vaultix](https://github.com/milieuim/vaultix) - Secret management
- [preservation](https://github.com/nix-community/preservation) - Opt-in state preservation
- [disko](https://github.com/nix-community/disko) - Declarative disk partitioning
- [lanzaboote](https://github.com/nix-community/lanzaboote) - Secure boot
- [treefmt-nix](https://github.com/numtide/treefmt-nix) - All-in-one formatter
- [devenv](https://github.com/cachix/devenv) - Developer environments
- [Cachix](https://www.cachix.org) - Binary cache for CI and local machines
- [RS-Key](https://github.com/TheMaxMur/RS-Key) - Security key. FIDO/OpenPGP firmware for RP2350

## Project Structure

- `nixos/`: NixOS system configurations
- `home-manager/`: Standalone Home Manager configurations
- `nix-on-droid/`: nix-on-droid configurations for Android
- `modules/`: Reusable Nix modules (NixOS, Home Manager, flake-parts)
- `pkgs/`: Custom packages (currently an empty scaffold)
- `overlays/`: Nixpkgs overlays
- `secrets/`: Encrypted secrets, managed by vaultix

## Hosts

Hostnames follow `<category>-<brand>-<model>[-<suffix>]`. The last segment only appears when there are multiple machines of the same model.

### NixOS

- `Laptop-Legion-R7000`: Main laptop
- `Server-IdeaPad-G480`: Home server
- `Router-RaspberryPi-4B-1`: Raspberry Pi 4B router

### nix-on-droid

- `Phone-Redmi-K50Pro`: Personal phone
- `Pad-Vivo-3Pro`: Tablet

## CI/CD

The build matrix is generated from the explicit list in `ci/jobs.nix`. NixOS hosts
come from `machines.nix`; Home Manager configurations are generated for those same
hosts; Android devices are listed by `droid.nix`.

- `CI`: gitleaks secret scan, legacy Flake health checks, actionlint, traditional evaluator checks, and Vaultix CLI wrapper builds
- Build: covers every NixOS toplevel, Home Manager activation and nix-on-droid activation; runs only when a commit touches build-related paths (`workflow_dispatch` forces a full run); aarch64 machines build on arm64 runners
- Build outputs are pushed to `curious.cachix.org`, so local `nixos-rebuild` / `home-manager switch` / `nix-on-droid` runs pull them directly
- `Update flake.lock`: weekly flake.lock update PR
- Dependabot: weekly updates for GitHub Actions

---

[![Nix Flake](https://img.shields.io/badge/Nix-Flake-blue.svg?logo=NixOS&logoColor=white)](https://nixos.wiki/wiki/Flakes)
