{
  description = "Curious's nix config";

  nixConfig = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    extra-substituters = [
      # 所有设备(跨类型)均需要使用的 substituter 写在此处
      # nix community's cache server
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      # nix community's cache server public key
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  # 这是 flake.nix 的标准格式，inputs 是 flake 的依赖，outputs 是 flake 的输出
  # inputs 中的每一项依赖都会在被拉取、构建后，作为参数传递给 outputs 函数
  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";

    # You can access packages and modules from different nixpkgs revs
    # at the same time. Here's an working example:
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # Also see the 'unstable-packages' overlay at 'overlays/default.nix'.

    flake-parts.url = "github:hercules-ci/flake-parts";

    # treefmt-nix
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      # `follows` 是 inputs 中的继承语法
      # 这里使 home-manager 的 `inputs.nixpkgs` 与当前 flake 的
      # `inputs.nixpkgs` 保持一致，避免依赖的 nixpkgs 版本不一致导致问题
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix on droid
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # TODO: Add any other flake you might need

    # Generate hardware-related configuration using the nixos-factor detection report
    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";

    # vaultix, a secret manage scheme for NixOS
    vaultix.url = "github:milieuim/vaultix";

    # 使 NixOS 不保留预期之外的副作用
    preservation.url = "github:nix-community/preservation";

    # Disko
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 一些项目官方仓库提供了自建的二进制缓存，这种情况下，为了充分利用缓存，
    # 引入时不应该令它的 inputs.nixpkgs 跟随我们的版本，这会导致
    # 产物与二进制缓存 hash 不一致，从而引起大量编译。
    # 典型的如 Helix 编辑器
    # helix.url = "github:helix-editor/helix/25.01.1";

    daeuniverse.url = "github:daeuniverse/flake.nix";

    yazi.url = "github:sxyazi/yazi";
  };

  # outputs 即 flake 的所有输出，其中的 nixosConfigurations 即 NixOS 系统配置
  # flake 有很多用途，也可以有很多不同的 outputs，nixosConfigurations 只是其中一种
  #
  # outputs 是一个函数，在 flake 评估时被隐式调用，inputs 将作为参数被传入，那么我们可以使用解构的方式
  # 声明参数集，即显式声明一些属性，这些属性会继承 inputs 中同名的属性，这使得 outputs 函数体中可以直接
  # 使用本地变量的名字来调用该依赖，比如 nixpkgs。我们不必将 inputs 中所有的属性都这样解构出来，不常用
  # 的非关键依赖可以不写，但这会导致解构赋值时产生匹配失败的错误，因此我们需要使用 ... 来承接未匹配的属性。
  # 同时，用 @ 语法给参数集起别名 inputs 后，函数中可以使用 inputs.<xxx> 的方式访问所有属性，即使它是前
  # 文所说的未解构的非关键依赖，这是flake 系统的 inputs 命名捕获在发挥作用。
  outputs =
    inputs@{
      self,
      flake-parts,
      treefmt-nix,
      vaultix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      top@{
        config,
        withSystem,
        moduleWithSystem,
        ...
      }:
      {
        imports = [
          treefmt-nix.flakeModule
          vaultix.flakeModules.default
          ./modules
          ./overlays
          ./nixos
          ./home-manager
          ./nix-on-droid
        ];

        systems = [
          "aarch64-linux"
          "i686-linux"
          "x86_64-linux"
          "aarch64-darwin"
          "x86_64-darwin"
        ];

        perSystem =
          { pkgs, ... }:
          {
            packages = import ./pkgs pkgs;
            treefmt = {
              projectRootFile = "flake.nix";
              settings.global.excludes = [
                "*.age"
                "secrets/cache/*"
              ];
              programs.nixfmt.enable = true;
              programs.prettier.enable = true;
            };
          };

        flake = {
          vaultix = {
            nodes = self.nixosConfigurations;
            cache = "./secrets/cache"; # default, optional
            identity = "/var/lib/vaultix/key.txt";
          };
        };
      }
    );
}
