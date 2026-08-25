# 🔐 Secrets Management

This directory contains encrypted secrets managed by [Vaultix](https://github.com/milieuim/vaultix), a secret management scheme for NixOS based on [age](https://github.com/FiloSottile/age).

## 📁 Structure

- `nixos/`: Secrets for NixOS configurations.
  - `common/`: Shared secrets (e.g., user passwords, database keys).
  - `<hostname>/`: Host-specific secrets (e.g., network credentials, private configs).
- `cache/`: Vaultix's internal cache for encrypted secrets. **Do not modify manually.**
- `vaultix.nix`: Vaultix project metadata.
- `vaultix-cli.nix`: Local edit and re-encryption wrappers.

## 🛠️ Usage

### Adding or Editing Secrets

Since Vaultix integrates with Nix, you can manage your secrets using the tools provided by the framework or the underlying `age` / `vaultix` CLI.

1.  **Identity Key**: Hosts decrypt from `/var/lib/vaultix/key.txt`.
2.  **Local commands**: Use the wrappers in `vaultix-cli.nix`; their identity is
    configured in `vaultix.nix`.

### Common Tasks

- **Update secrets**: Edit an `.age` file with the local editor wrapper:

  ```console
  nix run -f ./secrets/vaultix-cli.nix x86_64-linux.edit -- \
    ./secrets/nixos/example.age
  ```

  Re-encrypt all hosts after changing host keys or secret metadata:

  ```console
  nix run -f ./secrets/vaultix-cli.nix x86_64-linux.renc
  ```

- **Cache**: If you encounter issues with secrets not being picked up, check the `cache/` directory or the `vaultix` configuration in `vaultix.nix`.

## ⚠️ Security

- **Never** commit unencrypted secrets.
- **Always** ensure `.age` files are tracked by Git.
- The `secrets/cache/` directory is excluded from formatting by the repository's
  Prettier ignore rules and formatter script to avoid corruption.
