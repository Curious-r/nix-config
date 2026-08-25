let
  inherit (import ../lib/context.nix)
    machines
    mkInputs
    project
    sources
    ;

  mkHome =
    host: machine:
    let
      pkgs = import sources.nixpkgs {
        localSystem.system = machine.system;
      };
      homeManager = import sources.home-manager.outPath { inherit pkgs; };
      inputs = mkInputs pkgs;
    in
    homeManager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs project;
        self = project;
      };
      modules = [
        ./curious/${host}
        {
          nixpkgs = {
            overlays = builtins.attrValues project.overlays;
            config.allowUnfree = true;
          };
        }
      ];
    };
in
builtins.listToAttrs (
  map (host: {
    name = "curious@${host}";
    value = mkHome host machines.${host};
  }) (builtins.attrNames machines)
)
