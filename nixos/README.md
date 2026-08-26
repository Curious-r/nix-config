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

Since `nixos/default.nix` returns an attribute set of hosts, `--attr '<hostname>'`
selects one machine. `nixos-rebuild` then appends
`config.system.build.toplevel` internally.

`--file` also accepts the containing directory:

```bash
nixos-rebuild switch -f nixos --attr '<hostname>' --elevate run0
```

For a directory, it looks for `system.nix` first and then falls back to
`default.nix`. The directory fallback is an implementation detail of
`nixos-rebuild`, so prefer the explicit file in scripts.

This traditional entrypoint disables Flake auto-detection and does not require
channels or `NIX_PATH`: all sources are pinned in `npins/`.

Or use the Flake compatibility boundary:

```bash
nixos-rebuild switch --flake .#<hostname> --elevate run0
```

CI builds the toplevel for each host and pushes it to `curious.cachix.org`, so local rebuilds pull it directly.
