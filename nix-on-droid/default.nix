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
      # 必须显式指定 system：nixpkgs 顶层不认 stdenv.hostPlatform 参数，
      # 在 x86_64 机器上求值会静默退化成 x86_64，产物无法在手机上使用
      pkgs = import nixpkgs { system = "aarch64-linux"; };
      modules = [ ./Phone-Redmi-K50Pro ];
    };
    Pad-Vivo-3Pro = nix-on-droid.lib.nixOnDroidConfiguration {
      extraSpecialArgs = {
        inherit inputs;
      };
      pkgs = import nixpkgs { system = "aarch64-linux"; };
      modules = [ ./Pad-Vivo-3Pro ];
    };
  };
}
