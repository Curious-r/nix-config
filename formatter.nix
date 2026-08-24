{
  sources ? import ./npins,
  systems ? [
    "aarch64-linux"
    "x86_64-linux"
  ],
}:
let
  mkTools =
    system:
    let
      pkgs = import sources.nixpkgs {
        localSystem.system = system;
      };

      format = pkgs.writeShellApplication {
        name = "format";
        runtimeInputs = [
          pkgs.findutils
          pkgs.nixfmt
          pkgs.prettier
        ];
        text = ''
          find . \
            -path './.git' -prune -o \
            -path './.devenv' -prune -o \
            -path './.direnv' -prune -o \
            -name '.devenv.flake.nix' -prune -o \
            -path './secrets/cache' -prune -o \
            -type f -name '*.nix' -print0 \
            | xargs -0 --no-run-if-empty nixfmt

          prettier --write --ignore-unknown .
        '';
      };

      check =
        pkgs.runCommand "format-check"
          {
            nativeBuildInputs = [
              pkgs.findutils
              pkgs.nixfmt
              pkgs.prettier
            ];
            src = ./.;
          }
          ''
            cd "$src"
            find . \
              -path './.git' -prune -o \
              -path './.devenv' -prune -o \
              -path './.direnv' -prune -o \
              -name '.devenv.flake.nix' -prune -o \
              -path './secrets/cache' -prune -o \
              -type f -name '*.nix' -print0 \
              | xargs -0 --no-run-if-empty nixfmt --check

            prettier --check --ignore-unknown .
            touch "$out"
          '';
    in
    {
      inherit check format;
    };
in
builtins.listToAttrs (
  map (system: {
    name = system;
    value = mkTools system;
  }) systems
)
