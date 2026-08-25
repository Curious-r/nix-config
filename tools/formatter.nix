{
  sources ? import ../npins,
  root ? ./..,
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
          check=false
          targets=()

          for arg in "$@"; do
            case "$arg" in
              --check) check=true ;;
              --write) check=false ;;
              --)
                ;;
              -*)
                echo "Unsupported option: $arg" >&2
                exit 2
                ;;
              *) targets+=("$arg") ;;
            esac
          done

          if (( ''${#targets[@]} == 0 )); then
            targets=(.)
          fi

          nixfmtArgs=()
          prettierArgs=(--ignore-unknown)
          if [[ "$check" == true ]]; then
            nixfmtArgs+=(--check)
            prettierArgs+=(--check)
          else
            prettierArgs+=(--write)
          fi

          for target in "''${targets[@]}"; do
            find "$target" \
              -path '*/.git' -prune -o \
              -path '*/.devenv*' -prune -o \
              -path '*/.direnv' -prune -o \
              -name '.devenv.flake.nix' -prune -o \
              -path '*/secrets/cache' -prune -o \
              -type f -name '*.nix' -print0
          done \
            | xargs -0 --no-run-if-empty nixfmt "''${nixfmtArgs[@]}"

          prettier "''${prettierArgs[@]}" "''${targets[@]}"
        '';
      };

      check = pkgs.runCommand "format-check" { src = root; } ''
        cd "$src"
        "${format}/bin/format" --check .
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
