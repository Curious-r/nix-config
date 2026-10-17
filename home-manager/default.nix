let
  inherit (import ../lib/context.nix)
    sources
    overlays
    ;

  homeManagerModules = import ../modules/home-manager;
  nixosConfigurations = import ../nixos;

  mkHome =
    host: system:
    let
      pkgs = import sources.nixpkgs {
        localSystem.system = system;
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
    value = mkHome host nixosConfigurations.${host}.pkgs.stdenv.hostPlatform.system;
  }) (builtins.attrNames nixosConfigurations)
)
