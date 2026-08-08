[![Declarative](https://img.shields.io/badge/Declarative-Configuration-success)](https://builtwithnix.org/)
[![CI](https://github.com/Curious-r/nix-config/actions/workflows/ci.yml/badge.svg)](https://github.com/Curious-r/nix-config/actions/workflows/ci.yml)

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
- [RS-Key](https://github.com/TheMaxMur/RS-Key) - Security key. FIDO/OpenPGP firmware for RP2350

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

## 🤖 CI/CD

GitHub Actions 覆盖了 PR 和 main 的自动检查：

- `CI`:gitleaks 密钥扫描、flake.lock 健康检查、actionlint、`nix flake check`(含 aarch64-linux 求值)、x86_64 主机的 NixOS toplevel 与 home-manager 构建
- `Update flake.lock`:每周自动提交 flake.lock 更新 PR
- Dependabot:每周批量更新 GitHub Actions 版本

---

[![Nix Flake](https://img.shields.io/badge/Nix-Flake-blue.svg?logo=NixOS&logoColor=white)](https://nixos.wiki/wiki/Flakes)
