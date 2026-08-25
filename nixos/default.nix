let
  inherit (import ../lib/context.nix)
    machines
    mkInputs
    overlays
    project
    sources
    ;
  evalNixos = import "${sources.nixpkgs}/nixos/lib/eval-config.nix";

  mkSystem =
    name: machine:
    let
      pkgs = import sources.nixpkgs {
        localSystem.system = machine.system;
        overlays = builtins.attrValues overlays;
        config.allowUnfree = true;
      };
      inputs = mkInputs pkgs;
    in
    evalNixos {
      inherit pkgs;
      system = machine.system;
      specialArgs = {
        inherit inputs project;
        self = project;
      }
      // machine.specialArgs;
      modules = [
        { nixpkgs.flake.source = sources.nixpkgs.outPath; }
        {
          # The host package set is constructed once above. NixOS asserts that
          # legacy nixpkgs.config must not be merged into such an instance.
          nixpkgs.config = pkgs.lib.mkForce { };
        }
        ./common/core
        machine.module or (./. + "/${name}")
      ];
    };
in
builtins.mapAttrs mkSystem machines
