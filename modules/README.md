# 🚀 Custom Modules

This directory contains custom modules used in the project, which can also be utilized independently.

The true power of **Nix** lies in its modular system. Here, I've defined independent modules that can be imported or customized based on the exposed options.

---

### 🔗 Referencing Local Modules in Flake Parts

To reference a local module within your **flake-parts** setup, use the following syntax:

```nix
self.homeManagerModules.<module-name>
```

Simply replace `<module-name>` with the desired module name.

---

### 📚 Available Modules

- **`homeManagerModules`**:
  Modules compatible with **Home Manager**, designed to work across various OS-based host machines.
  If you like any element of my system then use the respective module.

- **`nixosModules`**:
  Modules specifically tailored for **NixOS**, leveraging NixOS-specific features and functionality.
  If you are advanced user then use this as this configures the Operating system at it's core.
  Expects `input, impermanence` as module arg. (disable them if you don't want to use them but import them.)

---

### 🛠️ Why Use These Modules?

- **Modular Design**: Import and tweak as needed for flexibility.
- **Independent Functionality**: Each module can work standalone or as part of a larger system.

---
