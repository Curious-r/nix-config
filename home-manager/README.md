# 🏠 Home Manager Configurations

Standalone Home Manager configurations for user environments.

## Users

- `curious`: Main user
  - `common/`: Shared user settings
  - `Laptop-Legion-R7000`: Host-specific overrides for the laptop
  - `Server-IdeaPad-G480`: Host-specific overrides for the server
  - `Router-RaspberryPi-4B-1`: Host-specific overrides for the router

## Deployment

Build a standalone activation package from the traditional entrypoint:

```bash
nix build -f home-manager.nix '"curious@<hostname>".activationPackage'
./result/activate
```

Or use the Flake compatibility boundary:

```bash
home-manager switch --flake .#curious@<hostname>
```

CI builds the activation package for each host and pushes it to `curious.cachix.org`, so local switches pull it directly.
