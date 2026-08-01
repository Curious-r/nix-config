# 🏠 Home Manager Configurations

Standalone Home Manager configurations for managing user environments.

## 👤 Users

- `curious`: Main user configuration.
  - `common/`: Shared user settings.
  - `Laptop-Legion-R7000`: Host-specific overrides for the laptop.
  - `Server-IdeaPad-G480`: Host-specific overrides for the server.
  -  `Router-RaspberryPi-4B1`: Host-specific overrides for the router.

## 🚀 Deployment

To apply the configuration using the standalone Home Manager tool:

```bash
home-manager switch --flake .#curious@<hostname>
```
