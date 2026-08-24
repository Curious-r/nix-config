{
  description = "Curious's Nix config";

  nixConfig = {
    extra-substituters = [
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      "https://mirrors.sjtug.sjtu.edu.cn/nix-channels/store"
      "https://nix-community.cachix.org"
      "https://cache.numtide.com"
      "https://curious.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "curious.cachix.org-1:5dkD/spZ5UAuL9K84Fy2xCdtfey1TAWj2RKUu2sjy3E="
    ];
  };

  outputs =
    _:
    let
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      sources = import ./npins;
      formatterTools = import ./formatter.nix { inherit sources systems; };

      pkgsFor =
        system:
        import sources.nixpkgs {
          localSystem.system = system;
        };

      packageSets = builtins.listToAttrs (
        map (system: {
          name = system;
          value = import ./pkgs (pkgsFor system);
        }) systems
      );

      vaultixMetadata = import ./vaultix.nix // {
        defaultSecretDirectory = "./secrets";
        nodes = import ./system.nix;
        app = import ./vaultix-cli.nix;
      };
    in
    {
      checks = builtins.mapAttrs (_: tools: {
        format-check = tools.check;
      }) formatterTools;

      ci.jobs = import ./ci/jobs.nix;

      formatter = builtins.mapAttrs (_: tools: tools.format) formatterTools;

      homeConfigurations = import ./home-manager.nix;
      homeManagerModules = import ./modules/home-manager;

      nixOnDroidConfigurations = import ./droid.nix;

      nixosConfigurations = import ./system.nix;
      nixosModules = import ./modules/nixos;

      overlays = import ./overlays;
      packages = packageSets;

      vaultix = vaultixMetadata;
    };
}
