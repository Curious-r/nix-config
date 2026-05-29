# 🔐 Secrets Management

This directory contains encrypted secrets managed by [Vaultix](https://github.com/milieuim/vaultix), a secret management scheme for NixOS based on [age](https://github.com/FiloSottile/age).

## 📁 Structure

- `nixos/`: Secrets for NixOS configurations.
    - `common/`: Shared secrets (e.g., user passwords, database keys).
    - `<hostname>/`: Host-specific secrets (e.g., network credentials, private configs).
- `cache/`: Vaultix's internal cache for encrypted secrets. **Do not modify manually.**

## 🛠️ Usage

### Adding or Editing Secrets

Since Vaultix integrates with Nix, you can manage your secrets using the tools provided by the framework or the underlying `age` / `vaultix` CLI.

1.  **Identity Key**: Your identity key is expected at `/var/lib/vaultix/key.txt` (as defined in `flake.nix`).
2.  **Encryption**: Files are encrypted using the public keys defined in the Vaultix configuration.

### Common Tasks

- **Update secrets**: Modify the `.age` files using your preferred age-compatible editor.
- **Cache**: If you encounter issues with secrets not being picked up, check the `cache/` directory or the `vaultix` configuration in `flake.nix`.

## ⚠️ Security

- **Never** commit unencrypted secrets.
- **Always** ensure `.age` files are tracked by Git.
- The `secrets/cache/` directory is excluded from formatting in `treefmt-nix` to avoid corruption.
