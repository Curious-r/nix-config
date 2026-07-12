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
    };
  };
}
