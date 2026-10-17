let
  inherit (import ../lib/context.nix)
    sources
    overlays
    ;

  nixosModules = import ../modules/nixos;
  evalNixos = import "${sources.nixpkgs}/nixos/lib/eval-config.nix";

  isHostDir =
    name: type:
    type == "directory" && name != "common" && builtins.pathExists (./. + "/${name}/default.nix");

  dirEntries = builtins.readDir ./.;
  hostNames = builtins.filter (name: isHostDir name dirEntries.${name}) (
    builtins.attrNames dirEntries
  );

  mkSystem =
    name:
    evalNixos {
      system = null;
      specialArgs = {
        inherit
          sources
          overlays
          nixosModules
          ;
      };
      modules = [
        {
          nixpkgs.overlays = builtins.attrValues overlays;
          nixpkgs.config.allowUnfree = true;
          nixpkgs.flake.source = sources.nixpkgs.outPath;
        }
        ./common/core
        (./. + "/${name}")
      ];
    };
in
builtins.listToAttrs (
  map (name: {
    inherit name;
    value = mkSystem name;
  }) hostNames
)
