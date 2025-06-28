{ inputs, ... }:
let
  # 维持传统 flake 中函数调用的惯用形式
  inherit (inputs) home-manager;
in

{
  # Standalone home-manager configuration entrypoint
  # Available through 'home-manager --flake .#your-username@your-hostname'
  flake.homeConfigurations = {
    # FIXME replace with your username@hostname
    "curious@Server-Ideapad-G480" = home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux; # Home-manager requires 'pkgs' instance
      extraSpecialArgs = {
        inherit inputs;
      };
      modules = [
        # > Our main home-manager configuration file <
        ./curious/Server-Ideapad-G480
      ];
    };
    "curious@Desktop-DIY-B650" = home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux; # Home-manager requires 'pkgs' instance
      extraSpecialArgs = {
        inherit inputs;
      };
      modules = [
        # > Our main home-manager configuration file <
        ./curious/Desktop-DIY-B650
      ];
    };
  };
}
