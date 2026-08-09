{ inputs, self, ... }:
let
  # 维持传统 flake 中函数调用的惯用形式
  inherit (inputs) home-manager;
in

{
  # Standalone home-manager configuration entrypoint
  # Available through 'home-manager --flake .#your-username@your-hostname'
  flake.homeConfigurations = {
    # FIXME replace with your username@hostname
    "curious@Server-IdeaPad-G480" = home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux; # Home-manager requires 'pkgs' instance
      extraSpecialArgs = {
        inherit inputs self;
      };
      modules = [
        # > Our main home-manager configuration file <
        ./curious/Server-IdeaPad-G480
        {
          nixpkgs = {
            # you can add global overlays here
            overlays = builtins.attrValues self.overlays;
            config = {
              allowUnfree = true;
            };
          };
        }
      ];
    };
    "curious@Laptop-Legion-R7000" = home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux; # Home-manager requires 'pkgs' instance
      extraSpecialArgs = {
        inherit inputs self;
      };
      modules = [
        # > Our main home-manager configuration file <
        ./curious/Laptop-Legion-R7000
        {
          nixpkgs = {
            # you can add global overlays here
            overlays = builtins.attrValues self.overlays;
            config = {
              allowUnfree = true;
            };
          };
        }
      ];
    };
    "curious@Router-RaspberryPi-4B-1" = home-manager.lib.homeManagerConfiguration {
      # 树莓派是 aarch64：固定 x86_64 会导致闭包平台错配，本地无法替换
      pkgs = inputs.nixpkgs.legacyPackages.aarch64-linux; # Home-manager requires 'pkgs' instance
      extraSpecialArgs = {
        inherit inputs self;
      };
      modules = [
        # > Our main home-manager configuration file <
        ./curious/Router-RaspberryPi-4B-1
        {
          nixpkgs = {
            # you can add global overlays here
            overlays = builtins.attrValues self.overlays;
            config = {
              allowUnfree = true;
            };
          };
        }
      ];
    };
  };
}
