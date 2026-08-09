{
  description = "Curious's nix config";

  nixConfig = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    extra-substituters = [
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      "https://mirrors.sjtug.sjtu.edu.cn/nix-channels/store"
      # nix community's cache server
      "https://nix-community.cachix.org"
      # numtide's cache server
      "https://cache.numtide.com"
      # 自己的 Cachix 缓存：CI 构建产物
      "https://curious.cachix.org"
    ];
    extra-trusted-public-keys = [
      # nix community's cache server public key
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      # numtide's cache server public key
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      # curious.cachix.org public key
      "curious.cachix.org-1:5dkD/spZ5UAuL9K84Fy2xCdtfey1TAWj2RKUu2sjy3E="
    ];
  };

  # 这是 flake.nix 的标准格式，inputs 是 flake 的依赖，outputs 是 flake 的输出
  # inputs 中的每一项依赖都会在被拉取、构建后，作为参数传递给 outputs 函数
  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    # treefmt-nix
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager";
      # `follows` 是 inputs 中的继承语法
      # 这里使 home-manager 的 `inputs.nixpkgs` 与当前 flake 的
      # `inputs.nixpkgs` 保持一致，避免依赖的 nixpkgs 版本不一致导致问题
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix on droid
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # TODO: Add any other flake you might need

    # Hardware collection
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
      # 与系统共用同一份 nixpkgs，避免锁文件里残留过期的独立 tarball 节点
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Vaultix, a secret manage scheme for NixOS
    vaultix = {
      url = "github:Curious-r/vaultix/merged-wip";
      # 与系统共用同一份 nixpkgs，消除独立的 nixpkgs_2 节点
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Authenticate PAM (e.g. polkit's run0) on a remote host by touching a FIDO2
    # authenticator plugged into your local workstation, over an SSH-forwarded Unix socket
    pam-fido-remote = {
      url = "git+https://codeberg.org/r-vdp/pam-fido-remote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 使 NixOS 不保留预期之外的副作用
    preservation.url = "github:nix-community/preservation";

    # Disko
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secure boot for NixOS
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 一些项目官方仓库提供了自建的二进制缓存，这种情况下，为了充分利用缓存，
    # 引入时不应该令它的 inputs.nixpkgs 跟随我们的版本，这会导致
    # 产物与二进制缓存 hash 不一致，从而引起大量编译。
    # 典型的如 Helix 编辑器
    # helix.url = "github:helix-editor/helix/25.01.1";

    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      # IMPORTANT: we're using "libgbm" and is only available in unstable so ensure
      # to have it up-to-date or simply don't specify the nixpkgs input
      inputs.nixpkgs.follows = "nixpkgs";
    };

    solaar = {
      # 用 GitHub 源而不是 flakehub tarball：Lix 锁定 tarball 时会追加 rev/revCount
      # 查询参数，而 Determinate Nix 解析时不带参数，导致干净环境（CI）报
      # "mismatch in field 'url'"
      url = "github:Svenum/Solaar-Flake/0.1.8";
      #url = "https://flakehub.com/f/Svenum/Solaar-Flake/0.1.1.tar.gz"; # uncomment line for solaar version 1.1.13
      #url = "github:Svenum/Solaar-Flake/main"; # Uncomment line for latest unstable version
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dms-plugin-registry = {
      url = "github:AvengeMedia/dms-plugin-registry";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # outputs 即 flake 的所有输出，其中的 nixosConfigurations 即 NixOS 系统配置
  # flake 有很多用途，也可以有很多不同的 outputs，nixosConfigurations 只是其中一种
  #
  # outputs 是一个函数，在 flake 评估时被隐式调用，inputs 将作为参数被传入，那么我们可以使用解构的方式
  # 声明参数集，即显式声明一些属性，这些属性会继承 inputs 中同名的属性，这使得 outputs 函数体中可以直接
  # 使用本地变量的名字来调用该依赖，比如 nixpkgs。我们不必将 inputs 中所有的属性都这样解构出来，不常用
  # 的非关键依赖可以不写；但如果声明了一个 inputs 里不存在的名字，会报 missing attribute 错误，因此需要
  # 用 ... 承接未列出的属性。同时，用 @ 语法给整个参数集起别名 inputs 后，函数体中可以通过 inputs.<xxx>
  # 访问任何属性，即使它没有被解构出来。
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
      let
        inherit (inputs) nixpkgs;
        lib = nixpkgs.lib;

        # GitHub Actions runner 标签映射（只覆盖当前实际使用的平台）
        runnerFor = {
          x86_64-linux = "ubuntu-latest";
          aarch64-linux = "ubuntu-24.04-arm";
        };

        # homeConfigurations 的键形如 "curious@Host"，取出主机名部分
        hmHost =
          key:
          let
            parts = lib.splitString "@" key;
          in
          if builtins.length parts != 2 then
            throw "ci.jobs: homeConfigurations 键 '${key}' 不符合 user@host 格式"
          else
            builtins.elemAt parts 1;

        # 机器清单直接来自各配置输出，加机器时 CI 自动覆盖
        machines = lib.unique (
          (builtins.attrNames self.nixosConfigurations)
          ++ (map hmHost (builtins.attrNames self.homeConfigurations))
          ++ (builtins.attrNames self.nixOnDroidConfigurations)
        );

        mkRow = target: machine: system: attr: prefetchPaths: {
          name = "${target} ${machine} (${system})";
          target = target;
          machine = machine;
          system = system;
          attr = attr;
          # nix-on-droid 硬编码的 bootstrap store path，构建前需先从
          # nix-on-droid.cachix.org 预取进本地 store（Nix 实例化时不查 substituter）
          prefetch = lib.concatStringsSep " " prefetchPaths;
          runsOn = runnerFor.${system} or (throw "ci.jobs: 没有为 ${system} 映射 GitHub runner（机器 ${machine}）");
          # nix-on-droid 求值依赖 builtins.currentSystem，需要 --impure
          impure = target == "nix-on-droid";
        };

        mkRows =
          machine:
          (lib.optional (builtins.hasAttr machine self.nixosConfigurations) (
            mkRow "nixos" machine self.nixosConfigurations.${machine}.config.system.build.toplevel.system
              "nixosConfigurations.${machine}.config.system.build.toplevel"
              [ ]
          ))
          ++ (lib.optional (builtins.hasAttr "curious@${machine}" self.homeConfigurations) (
            mkRow "home-manager" "curious@${machine}"
              self.homeConfigurations."curious@${machine}".activationPackage.system
              "homeConfigurations.\"curious@${machine}\".activationPackage"
              [ ]
          ))
          ++ (lib.optional (builtins.hasAttr machine self.nixOnDroidConfigurations) (
            let
              droid = self.nixOnDroidConfigurations.${machine};
            in
            mkRow "nix-on-droid" machine droid.config.build.activationPackage.system
              "nixOnDroidConfigurations.${machine}.config.build.activationPackage"
              [ droid.config.environment.files.prootStatic ]
          ));

        ciJobs = builtins.sort (a: b: a.name < b.name) (lib.concatLists (map mkRows machines));
      in
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
              programs = {
                nixfmt.enable = true;
                prettier.enable = true;
              };
            };
            vaultix.extraPackages = [ pkgs.age-plugin-yubikey ];
          };

        flake = {
          # CI 构建矩阵：由各配置输出自动推导，避免手写清单漂移
          ci = {
            jobs = ciJobs;
          };

          vaultix = {
            nodes = self.nixosConfigurations;
            cache = "./secrets/cache";
            identity = ./secrets/yubikey-vaultix-stub.txt;
            extraRecipients = [
              "age1x8a36nac7w9fr8ajnng0ft65z2m2uctw6u57tnsvkt8yxjfdlddsrgjr8n"
            ];
          };
        };
      }
    );
}
