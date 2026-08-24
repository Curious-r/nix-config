let
  inherit (import ./context.nix)
    machines
    mkInputs
    project
    sources
    ;

  homeManager = import sources.home-manager.outPath { };

  mkHome =
    host: machine:
    let
      pkgs = import sources.nixpkgs {
        localSystem.system = machine.system;
      };
      inputs = mkInputs pkgs;
    in
    homeManager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs project;
        self = project;
      };
      modules = [
        ./home-manager/curious/${host}
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
