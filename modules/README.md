# Custom Modules

Reusable modules from this flake, usable from other configurations as well.

## Referencing Local Modules in flake-parts

```nix
self.homeManagerModules.<module-name>
```

Replace `<module-name>` with the module you want.

## Available Modules

- `homeManagerModules`: Home Manager modules, designed to work on any host machine.
- `nixosModules`: NixOS-specific modules, configuring the OS at its core. They expect `inputs` and `preservation` as module args (disable them if you don't want to use them, but keep the imports).
- `flakeModules`: flake-parts modules distributed through the flake. Currently only `example-parts`. Importing from `self` is not possible because such an import would affect the `self` attribute set; reference the exported module directly instead. See https://flake.parts/dogfood-a-reusable-module.html
