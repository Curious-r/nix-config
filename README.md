[![Declarative](https://img.shields.io/badge/Declarative-Configuration-success)](https://builtwithnix.org/)
[![CI](https://github.com/Curious-r/nix-config/actions/workflows/ci.yml/badge.svg)](https://github.com/Curious-r/nix-config/actions/workflows/ci.yml)

# ❄️ Curious's Nix Config

Personal NixOS, Home Manager and nix-on-droid configurations evaluated directly
from npins-pinned sources. A small Flake remains available as an optional
compatibility boundary.

## Tech Stack

- [Lix](https://git.lix.systems/lix-project/lix) - A delicious Nix fork
- [npins](https://github.com/andir/npins) - Source pinning for traditional Nix evaluation
- [vaultix](https://github.com/milieuim/vaultix) - Secret management
- [preservation](https://github.com/nix-community/preservation) - Opt-in state preservation
- [disko](https://github.com/nix-community/disko) - Declarative disk partitioning
- [lanzaboote](https://github.com/nix-community/lanzaboote) - Secure boot
- [devenv](https://github.com/cachix/devenv) - Developer environments
- [Cachix](https://www.cachix.org) - Binary cache for CI and local machines
- [RS-Key](https://github.com/TheMaxMur/RS-Key) - Security key. FIDO/OpenPGP firmware for RP2350

## Project Structure

- `lib/`: Shared evaluation context and host inventory
- `nixos/`: NixOS system configurations and their evaluation entrypoint
- `home-manager/`: Home Manager configurations used standalone and through NixOS,
  with the standalone evaluation entrypoint in `default.nix`
- `nix-on-droid/`: nix-on-droid configurations, with the evaluation entrypoint in
  `default.nix`
- `modules/`: Reusable Nix modules (NixOS, Home Manager)
- `ci/jobs.nix`: Explicit build matrix
- `npins/`: Pinned upstream sources
- `pkgs/`: Custom packages
- `overlays/`: Nixpkgs overlays
- `secrets/`: Encrypted secrets, Vaultix metadata and local editing wrappers
- `tools/`: Repository maintenance tools

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
come from `lib/machines.nix`; Home Manager configurations are generated for those
same hosts; Android devices are listed by `nix-on-droid/default.nix`.

### Formatting

Format tracked Nix and Prettier-supported files:

```console
nix run -f ./tools/formatter.nix x86_64-linux.format
```

The optional Flake boundary also exposes this as `nix fmt`.

- `CI`: gitleaks secret scan, actionlint, Flake compatibility and formatter checks, traditional evaluator checks, and Vaultix CLI wrapper builds
- Build: covers every NixOS toplevel, Home Manager activation and nix-on-droid activation; runs only when a commit touches build-related paths (`workflow_dispatch` forces a full run); aarch64 machines build on arm64 runners
- Build outputs are pushed to `curious.cachix.org`, so local builds and activations pull reusable paths directly
- `Update npins sources`: weekly npins update PR
- Dependabot: weekly updates for GitHub Actions
