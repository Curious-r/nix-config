let
  sources = import ../npins;
  pkgs = import sources.nixpkgs { };

  evalNixos = import "${sources.nixpkgs}/nixos/lib/eval-config.nix";

  # Placeholder Sprout package satisfying types.package and providing lib/sprout/sprout.efi
  # without building or executing a real EFI binary.
  placeholderSprout = pkgs.runCommand "sprout-placeholder" { } ''
    mkdir -p $out/lib/sprout
    touch $out/lib/sprout/sprout.efi
  '';

  eval = evalNixos {
    system = "x86_64-linux";
    modules = [
      ../modules/nixos/sprout.nix
      {
        system.stateVersion = "24.11";
        boot.loader.sprout.enable = true;
        boot.loader.sprout.package = placeholderSprout;
        fileSystems."/".device = "/dev/dummy";
        fileSystems."/".fsType = "ext4";
      }
    ];
  };
in
eval.config.system.build.installBootLoader
