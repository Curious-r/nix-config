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
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    # You can access packages and modules from different nixpkgs revs
    # at the same time. Here's an working example:
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # Also see the 'unstable-packages' overlay at 'overlays/default.nix'.

    # 使系统不保留预期之外的副作用
    impermanence.url = "github:nix-community/impermanence";

    # Disko
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
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
    # hardware.url = "github:nixos/nixos-hardware";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    helix = {
      url = "github:helix-editor/helix/25.01.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    daeuniverse = {
      url = "github:daeuniverse/flake.nix/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-cosmic = {
      url = "github:lilyinstarlight/nixos-cosmic";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    yazi.url = "github:sxyazi/yazi";

    # Shameless plug: looking for a way to nixify your themes and make
    # everything match nicely? Try nix-colors!
    # nix-colors.url = "github:misterio77/nix-colors";
  };

  # outputs 即 flake 的所有输出，其中的 nixosConfigurations 即 NixOS 系统配置
  # flake 有很多用途，也可以有很多不同的 outputs，nixosConfigurations 只是其中一种
  #
  # outputs 是一个函数，它的参数都在 inputs 中定义，可以通过 inputs 中定义的名称来引用
  # 比如这里的输入参数 `nixpkgs`，就是上面 inputs 中的 `nixpkgs`
  # 不过 self 是个例外，这个特殊参数指向 outputs 自身（自引用），以及 flake 根目录
  # 这里的 @ 语法将函数的参数 attribute set 取了个别名，方便在内部使用
  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-on-droid,
      ...
    }@inputs:
    let
      inherit (self) outputs;
      # Supported systems for your flake packages, shell, etc.
      systems = [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      # This is a function that generates an attribute by calling a function you
      # pass to it, with each system as an argument
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # Your custom packages
      # Accessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});
      # Formatter for your nix files, available through 'nix fmt'
      # Other options beside 'alejandra' include 'nixpkgs-fmt'
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);

      # Your custom packages and modifications, exported as overlays
      overlays = import ./overlays { inherit inputs; };
      # Reusable nixos modules you might want to export
      # These are usually stuff you would upstream into nixpkgs
      nixosModules = import ./modules/nixos;
      # Reusable home-manager modules you might want to export
      # These are usually stuff you would upstream into home-manager
      homeManagerModules = import ./modules/home-manager;

      # NixOS configuration entrypoint
      # Available through 'nixos-rebuild --flake .#your-hostname'
      # 名为 nixosConfigurations 的 outputs 会在执行 `sudo nixos-rebuild switch`
      # 时被使用，默认情况下上述命令会使用与主机 hostname 同名的 nixosConfigurations
      # 但是也可以通过 `--flake /path/to/flake/direcotry#nixos-test` 来指定
      # 在 flakes 配置文件夹中执行如下命令即可部署此配置：
      #     sudo nixos-rebuild switch --flake .#nixos-test
      # 其中 --flake 后的参数简要说明如下：
      #   1. `.` 表示使用当前文件夹的 Flakes 配置，
      #   2. `#` 后面的内容则是 nixosConfigurations 的名称
      nixosConfigurations = {
        # FIXME replace with your hostname
        Server-Ideapad-G480 = nixpkgs.lib.nixosSystem {
          # Nixpkgs 的模块系统提供了两种方式来传递非默认参数：
          #   1. nixpkgs.lib.nixosSystem 函数的 specialArgs 参数
          #   2. 在任一 Module 中使用 _module.args 这个 option 来传递参数
          # specialArgs 与 _module.args 需要的值都是一个 attribute set，它们的功能也相同，
          # 都是将其 attribute set 中的所有参数传递到所有子模块中。这两者的区别在于：
          #   1. 在任何 Module 中都能使用 _module.args 这个 option，通过它互相传递参数，
          #      这要比只能在 nixpkgs.lib.nixosSystem 函数中使用的 specialArgs 更灵活
          #   2. _module.args 是在 Module 中声明使用的，因此必须在所有 Modules 都已经被求值后，
          #      才能使用它。这导致如果你在 imports = [ ... ]; 中使用 _module.args 传递的参数，
          #      会报错 infinite recursion，这种场景下你必须改用 specialArgs 才行
          # 以上来自 Ryin 的 NixOS 教程。此外，模块系统还有一种方式来带参数地引入其他文件：
          #   该文件必须是一个返回值为属性集的函数，在 imports = [ ... ]; 内使用括号包裹的 import 原语，形式如下：
          #     imports = [ (import ./a.nix { b = "c" }) ];
          #   或 flakes 组织的 NixOS 配置的 modules 列表钟：
          #     modules = [ (import ./a.nix { b = "c" }) ];
          #   这个方式携带的参数只有被调用的文件内可以使用，
          #   并且被引入的文件中也不可以使用 lib 、 config 这类由模块系统的自动注入的参数
          #   原因是这个文件并不是被当作模块对待的，尽管从文件内容的形式上看它可能完全符合模块的要求，
          #   但在这种调用方式下，括号内的表达式会先被求解，具体过程是这样的：
          #   以路径 ./a.nix 为参数调用 imports 函数，
          #   返回./a.nix 中定义的函数，然后以 { b = "c" } 为参数调用该函数，返回一个属性集，
          #   接下来的处理过程就和直接写在 imports 列表里的内联属性集一样了，所谓内联属性集就是我们常见的以下形式：
          #     imports = [ { a = b } ];
          #   和：
          #     modules = [ { a = b } ];
          #   一个单纯的属性集没有能接受参数的结构，模块系统无法对其注入，所以只能在其中进行 config 的定义，
          #   它适合简单、局部的配置定义，写起来比较方便
          specialArgs = {
            inherit inputs outputs;
            primaryDiskWwid = "ata-Phison_SATA_SSD_0C3307050CA900023301";
            swapSize = "8G";
            backupRetentionPolicy = "30"; # 备份旧快照的最长保留时间，单位为天
            enableRestoreService = false; # 恢复到某个备份时，配置此项为 true
            # restoreTarget = "";         # 并把此项的值修改为对应的时间戳
          };
          modules = [
            # > Our main nixos configuration file <
            ./nixos/generic/core
            ./nixos/generic/optional/nix/substituters/mainland.nix
            # ./nixos/generic/optional/nix/substituters/yazi.nix
            ./nixos/generic/optional/impermanence/basic
            ./nixos/generic/optional/impermanence/implementation/btrfs-subvolume.nix
            ./nixos/Server-Ideapad-G480
            # inputs.daeuniverse.nixosModules.dae
            # inputs.nixos-cosmic.nixosModules.default
          ];
        };
        Desktop-DIY-B650 = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
            primaryDiskWwid = "ata-WDC_PC_SN520_SDAPNUW-512G_19529C801253";
            swapSize = "16G";
            backupRetentionPolicy = "30"; # 备份旧快照的最长保留时间，单位为天
            enableRestoreService = false; # 恢复到某个备份时，配置此项为 true
            # restoreTarget = "";         # 并把此项的值修改为对应的时间戳
          };
          modules = [
            # > Our main nixos configuration file <
            ./nixos/generic/core
            ./nixos/generic/optional/nix/substituters/mainland.nix
            ./nixos/generic/optional/nix/substituters/cosmic.nix
            ./nixos/generic/optional/impermanence/basic
            ./nixos/generic/optional/impermanence/implementation/btrfs-subvolume.nix
            ./nixos/generic/optional/impermanence/additional/curious/desktop.nix
            ./nixos/Desktop-DIY-B650
            inputs.nixos-cosmic.nixosModules.default
          ];
        };
      };

      # Standalone home-manager configuration entrypoint
      # Available through 'home-manager --flake .#your-username@your-hostname'
      homeConfigurations = {
        # FIXME replace with your username@hostname
        "curious@Server-Ideapad-G480" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux; # Home-manager requires 'pkgs' instance
          extraSpecialArgs = {
            inherit inputs outputs;
          };
          modules = [
            # > Our main home-manager configuration file <
            ./home-manager/curious/Server-Ideapad-G480
          ];
        };
      };

      # Nix on droid configuration entrypoint
      # Available through 'nix-on-droid --flake .#FIXME'
      nixOnDroidConfigurations = {
        Phone-Redmi-K50Pro = nix-on-droid.lib.nixOnDroidConfiguration {
          extraSpecialArgs = {
            inherit inputs outputs;
          };
          pkgs = import nixpkgs { system = "aarch64-linux"; };
          modules = [ ./nix-on-droid/Phone-Redmi-K50Pro ];
        };
        Pad-Vivo-3Pro = nix-on-droid.lib.nixOnDroidConfiguration {
          extraSpecialArgs = {
            inherit inputs outputs;
          };
          pkgs = import nixpkgs { system = "aarch64-linux"; };
          modules = [ ./nix-on-droid/Pad-Vivo-3Pro ];
        };

      };
    };
}
