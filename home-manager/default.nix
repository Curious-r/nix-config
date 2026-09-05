let
  inherit (import ../lib/context.nix)
    machines
    sources
    overlays
    thirdPartyPackages
    ;

  homeManagerModules = import ../modules/home-manager;

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
        inherit
          sources
          overlays
          homeManagerModules
          thirdPartyPackages
          ;
      };
      modules = [
        ./curious/${host}
        {
          nixpkgs = {
            overlays = builtins.attrValues overlays;
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
