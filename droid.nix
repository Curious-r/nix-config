let
  inherit (import ./context.nix) sources;

  mkDroid =
    device:
    import "${sources.nix-on-droid}/modules" {
      # The upstream bootstrap package is keyed by this target, so never let it
      # fall back to the machine running the evaluation.
      targetSystem = "aarch64-linux";
      home-manager-path = sources.home-manager.outPath;
      pkgs = import sources.nixpkgs {
        localSystem.system = "aarch64-linux";
      };
      config.imports = [ ./nix-on-droid/${device} ];
      isFlake = true;
    };
in
{
  Phone-Redmi-K50Pro = mkDroid "Phone-Redmi-K50Pro";
  Pad-Vivo-3Pro = mkDroid "Pad-Vivo-3Pro";
}
