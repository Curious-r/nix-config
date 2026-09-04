{
  pkgs,
  sources,
}:

let
  inherit (pkgs) lib;

  source = sources."llm-agents.nix";

  # Reuse the upstream lib extensions (licenses, maintainers, etc.) without
  # importing the upstream flake or its development-time inputs.
  flake = {
    lib = import "${source}/lib" {
      inputs = {
        nixpkgs = {
          lib = pkgs.lib;
        };
      };
    };
  };

  interpolate = import "${source}/lib/interpolate.nix";

  fetchurlTemplate = import "${source}/lib/fetchurl-template.nix" {
    inherit (pkgs) fetchurl;
    inherit interpolate;
  };

  platformSource = import "${source}/lib/platform-source.nix" {
    inherit (pkgs) stdenv;
    inherit fetchurlTemplate;
  };

  mkUpdater = import "${source}/lib/mk-updater.nix" {
    inherit lib;
  };

  packageNames = builtins.filter (name: name != "default") (
    builtins.attrNames (
      lib.filterAttrs (_name: type: type == "directory") (builtins.readDir "${source}/packages")
    )
  );

  scope = lib.makeScope pkgs.newScope (
    self:
    {
      inherit
        flake
        interpolate
        fetchurlTemplate
        platformSource
        mkUpdater
        ;

      # Keep the same package-set fixed point expected by upstream packages.
      # The upstream `default` launcher is intentionally excluded above because
      # it eagerly walks this entire set and causes recursive evaluation in the
      # consumer environment.
      allPackages = packages;
    }
    // lib.genAttrs packageNames (name: self.callPackage "${source}/packages/${name}/package.nix" { })
  );

  packages = lib.genAttrs packageNames (name: scope.${name});
in
packages
