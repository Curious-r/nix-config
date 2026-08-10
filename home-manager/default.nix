{
  inputs,
  self,
  withSystem,
  ...
}:
let
  # 维持传统 flake 中函数调用的惯用形式。
  inherit (inputs) home-manager;

  # 按主机生成 home-manager 配置：pkgs 取自 flake-parts 对应 system 的 perSystem 配置，
  # 避免手写 legacyPackages 与机器实际平台脱节。
  mkHome =
    system: host:
    withSystem system (
      { pkgs, ... }:
      home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit inputs self;
        };
        modules = [
          # > Our main home-manager configuration file <
          ./curious/${host}
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
      }
    );
in

{
  # Standalone home-manager configuration entrypoint
  # Available through 'home-manager --flake .#your-username@your-hostname'
  flake.homeConfigurations = {
    # FIXME replace with your username@hostname
    "curious@Server-IdeaPad-G480" = mkHome "x86_64-linux" "Server-IdeaPad-G480";
    "curious@Laptop-Legion-R7000" = mkHome "x86_64-linux" "Laptop-Legion-R7000";
    "curious@Router-RaspberryPi-4B-1" = mkHome "aarch64-linux" "Router-RaspberryPi-4B-1";
  };
}
