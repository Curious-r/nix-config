{ self, ... }:
{
  flake.overlays = {
    # This one brings our custom packages from the 'pkgs' directory.
    # Note: use `final` directly, NOT `final.pkgs`. nixpkgs has a
    # self-reference `pkgs.pkgs = pkgs` for historical compatibility, so
    # `final.pkgs` technically works but is an unnecessary indirection.
    # See: https://github.com/Misterio77/nix-starter-configs/blob/main/standard/overlays/default.nix
    additions = final: _prev: import ../pkgs final;

    # This one contains whatever you want to overlay
    # You can change versions, add patches, set compilation flags, anything really.
    # https://nixos.wiki/wiki/Overlays
    modifications = final: prev: {
      # example = prev.example.overrideAttrs (oldAttrs: rec {
      # ...
      # });

      # 临时修复 py 3.14 引起的 khal 构建失败：使用 overrideScope 局部修改 python3Packages 作用域
      khal = prev.khal.override {
        python3Packages = prev.python3Packages.overrideScope (
          pythonFinal: pythonPrev: {
            click-threading = pythonPrev.click-threading.overridePythonAttrs (old: {
              doCheck = false;
            });
          }
        );
      };
    };
  };
}
