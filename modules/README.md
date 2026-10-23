# Custom Modules

Reusable modules imported directly by this repository.

## Using Modules

Import these sets from their source paths:

```nix
nixosModules = import ./modules/nixos;
homeManagerModules = import ./modules/home-manager;
```

The optional Flake boundary exports the same sets as `nixosModules` and
`homeManagerModules`.

## Available Modules

- `homeManagerModules`: an empty set reserved for reusable Home Manager modules.
- `nixosModules`: self-contained NixOS modules, currently including `daed`, `ddns-go`, and `sprout`.

### Sprout (`modules/nixos/sprout.nix`)

Sprout is a lightweight UEFI bootloader for NixOS featuring transactional, atomic bootloader installation and generation management.

#### Custom EFI Files (`boot.loader.sprout.extraFiles`)

The `boot.loader.sprout.extraFiles` option allows installing individual EFI binaries, kernels, or initrds from the Nix store into a module-managed ESP directory (`EFI/Sprout/extra-files/`).

```nix
boot.loader.sprout.extraFiles = {
  memtest = pkgs.memtest86plus + "/memtest.efi";
};
```

- **Attribute names**: Each attribute name serves as a logical identifier matching `[A-Za-z_][A-Za-z0-9_]*`.
- **Individual file paths**: The option accepts individual file paths, not package directories.
- **Module-managed destination**: Files are installed under content-addressed names (`<name>-<sha256><source-suffixes>`) in `EFI/Sprout/extra-files/`.
- **Referencing in settings**: Each extra file is exposed in `sprout.toml` through a root value named `sprout_extra_file_<name>`. Custom actions defined in `boot.loader.sprout.settings.actions` can reference them using `$sprout_extra_file_<name>`:

```nix
boot.loader.sprout.settings = {
  entries.memtest = {
    title = "Memtest86+";
    actions = [ "run-memtest" ];
  };
  actions.run-memtest = {
    chainload.path = "$sprout_extra_file_memtest";
  };
};
```

Extra files are staged transactionally with automatic rollback on pre-publication failure and cleaned up by garbage collection when no longer declared.

#### Boot Phases (`boot.loader.sprout.settings.phases`)

The `boot.loader.sprout.settings.phases` option configures actions executed during Sprout's static boot phases:

- **`early`**: Runs before filesystem drivers load.
- **`startup`**: Runs after drivers load and before the boot menu is displayed.
- **`late`**: Runs after a menu entry is selected and before its entry actions execute.

Each phase accepts an ordered list of items:

- `actions`: A required non-empty list of action names defined in `boot.loader.sprout.settings.actions`.
- `values`: An optional attribute set of phase-local string values for variable expansion in action definitions (e.g. `$variable`).

```nix
boot.loader.sprout.settings = {
  actions = {
    announce = {
      print.text = "$message";
    };
  };

  phases = {
    early = [
      {
        actions = [ "announce" ];
        values.message = "Initializing boot environment...";
      }
    ];

    startup = [
      {
        actions = [ "announce" ];
        values.message = "Preparing boot menu...";
      }
    ];

    late = [
      {
        actions = [ "announce" ];
        values.message = "Starting selected operating system...";
      }
    ];
  };
};
```

#### Root Values (`boot.loader.sprout.settings.values`)

The `boot.loader.sprout.settings.values` option configures shared default root-level string values for variable expansion across Sprout configurations:

- **Shared defaults**: Root values define shared string variables that can be referenced in static action paths (e.g. `$tools_dir`), phase configurations, or other nested root values.
- **Precedence**: Narrower entry-local and phase-local `values` retain precedence over root values and override them within their local scope.
- **Managed extra files**: `boot.loader.sprout.extraFiles` owns the reserved `sprout_extra_file_` prefix, exposing installed EFI files as root values (`$sprout_extra_file_<name>`), and remains the supported mechanism for installing individual files onto the ESP.

```nix
boot.loader.sprout.settings = {
  values = {
    tools_dir = "\\EFI\\tools";
    shell_bin = "$tools_dir\\Shell.efi";
  };

  actions = {
    uefi-shell = {
      chainload.path = "$shell_bin";
    };
  };

  entries = {
    shell = {
      title = "UEFI Shell";
      actions = [ "uefi-shell" ];
    };
  };
};
```
