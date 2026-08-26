# 🖥️ NixOS Configurations

This directory contains the NixOS hosts managed by this repository.

## Layout

- `common/core/`: settings imported by every host
- `common/optional/`: shared modules that individual hosts opt into
- `Laptop-Legion-R7000/`: main laptop
- `Server-IdeaPad-G480/`: home server
- `Router-RaspberryPi-4B-1/`: Raspberry Pi 4B router

## Rebuild a host

From the repository root, run:

```bash
nixos-rebuild switch \
  --file nixos/default.nix \
  --attr '<hostname>' \
  --elevate run0
```

Replace `<hostname>` with a key from `nixos/default.nix`, such as
`Laptop-Legion-R7000`.

That entrypoint returns an attribute set whose keys are hostnames. The
`--attr` option selects one host, and `nixos-rebuild` then builds:

```text
<hostname>.config.system.build.toplevel
```

To inspect what a rebuild would do without activating it, use:

```bash
nixos-rebuild dry-build \
  --file nixos/default.nix \
  --attr '<hostname>'
```

To build a new toplevel and create the usual `result` symlink without
activating it, use:

```bash
nixos-rebuild build \
  --file nixos/default.nix \
  --attr '<hostname>'
```

## Shorter `--file` form

`nixos-rebuild` also accepts the containing directory:

```bash
nixos-rebuild switch -f nixos --attr '<hostname>' --elevate run0
```

For a directory, it looks for `system.nix` first and then falls back to
`default.nix`. The fallback behavior is an implementation detail, so prefer the
explicit filename in scripts and documentation.

## Flake compatibility

The repository still exposes the same hosts through a small Flake boundary:

```bash
nixos-rebuild switch --flake ".#<hostname>" --elevate run0
```

`--file` and `--flake` are alternatives; do not combine them.

Use this when a tool expects a Flake URI. Day-to-day rebuilds can use the
traditional entrypoint above.

## Binary cache

CI builds every host toplevel and pushes it to `curious.cachix.org`. Local
rebuilds therefore download most unchanged paths instead of rebuilding them.
