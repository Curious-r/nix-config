# 📱 nix-on-droid Configurations

Nix-based environments for Android devices using [nix-on-droid](https://github.com/nix-community/nix-on-droid).

## Devices

- `Phone-Redmi-K50Pro`: Xiaomi Redmi K50 Pro
- `Pad-Vivo-3Pro`: Vivo Pad 3 Pro

## Deployment

Inside the nix-on-droid app on the device:

```bash
nix-on-droid switch --flake .#<device-name>
```

CI builds both device activations on arm64 runners and pushes them to `curious.cachix.org`. The device config already subscribes to `nix-on-droid.cachix.org` and `curious.cachix.org`.
