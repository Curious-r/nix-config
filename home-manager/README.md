# 🏠 Home Manager Configurations

Standalone Home Manager configurations for managing user environments.

## 👤 Users

- `curious`: Main user configuration.
  - `common/`: Shared user settings.
  - `Laptop-Legion-R7000`: Host-specific overrides for the laptop.
  - `Server-Ideapad-G480`: Host-specific overrides for the server.

## 🚀 Deployment

To apply the configuration using the standalone Home Manager tool:

```bash
home-manager switch --flake .#curious@<hostname>
```
