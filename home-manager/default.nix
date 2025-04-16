{ inputs, ... }:
let
  # 维持传统 flake 中流行的 inputs 参数解构的调用习惯
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
        ./curious/generic/core
        ./curious/generic/optional/nix/substituters/mainland.nix
        ./curious/Server-Ideapad-G480
      ];
    };
  };
}
