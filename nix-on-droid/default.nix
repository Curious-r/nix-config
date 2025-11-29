{ inputs, ... }:
let
  # 维持传统 flake 中函数调用的惯用形式
  inherit (inputs) nix-on-droid;
  inherit (inputs) nixpkgs;
in

{
  # Nix on droid configuration entrypoint
  # Available through 'nix-on-droid --flake .#FIXME'
  flake.nixOnDroidConfigurations = {
    Phone-Redmi-K50Pro = nix-on-droid.lib.nixOnDroidConfiguration {
      extraSpecialArgs = {
        inherit inputs;
      };
      pkgs = import nixpkgs { stdenv.hostPlatform.system = "aarch64-linux"; };
      modules = [ ./Phone-Redmi-K50Pro ];
    };
    Pad-Vivo-3Pro = nix-on-droid.lib.nixOnDroidConfiguration {
      extraSpecialArgs = {
        inherit inputs;
      };
      pkgs = import nixpkgs { stdenv.hostPlatform.system = "aarch64-linux"; };
      modules = [ ./Pad-Vivo-3Pro ];
    };
  };
}
