let
  inherit (import ../lib/context.nix) sources;

  # Keep the CLI separate from lib/context.nix: re-encryption needs every evaluated
  # host, while host evaluation only needs Vaultix's static project metadata.
  nodes = import ../nixos;

  systems = [
    "i686-linux"
    "x86_64-linux"
    "aarch64-linux"
  ];

  mkApps =
    system:
    let
      pkgs = import sources.nixpkgs {
        localSystem.system = system;
      };
      nixPackagesSources = import "${sources.nix-packages}/npins";
      nixPackages = import "${sources.nix-packages}/lib" {
        inherit pkgs;
      };
      package = nixPackages.vaultix;
      vaultix = import ./vaultix.nix;
      common = {
        inherit nodes package;
        inherit (vaultix) cache identity extraRecipients;
        lib = pkgs.lib;
        pkgs = pkgs;
        extraPackages = [ pkgs.age-plugin-yubikey ];
        pinentryPackage = null;
      };
    in
    {
      renc = pkgs.callPackage "${nixPackagesSources.vaultix}/apps/renc.nix" common;
      edit = pkgs.callPackage "${nixPackagesSources.vaultix}/apps/edit.nix" common;
    };
in
builtins.listToAttrs (
  map (system: {
    name = system;
    value = mkApps system;
  }) systems
)
