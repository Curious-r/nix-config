let
  inherit (import ./context.nix) machines sources;

  # Keep the CLI separate from context.nix: re-encryption needs every evaluated
  # host, while host evaluation only needs Vaultix's static project metadata.
  nodes = import ./system.nix;

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
      package = (import ./third-party-packages.nix { inherit sources; }).vaultix pkgs;
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
      renc = pkgs.callPackage "${sources.vaultix}/apps/renc.nix" common;
      edit = pkgs.callPackage "${sources.vaultix}/apps/edit.nix" common;
    };
in
builtins.listToAttrs (
  map (system: {
    name = system;
    value = mkApps system;
  }) systems
)
