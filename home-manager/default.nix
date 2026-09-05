let
  inherit (import ../lib/context.nix)
    machines
    project
    sources
    thirdPartyPackages
    ;

  mkHome =
    host: machine:
    let
      pkgs = import sources.nixpkgs {
        localSystem.system = machine.system;
      };
      homeManager = import sources.home-manager.outPath { inherit pkgs; };
    in
    homeManager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit sources thirdPartyPackages project;
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
