{ inputs, self, ... }:
let
  # 维持传统 flake 中函数调用的惯用形式
  inherit (inputs) nixpkgs;
in
{
  flake.nixosConfigurations = {
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
      # 以上来自 ryan4yin 的 NixOS 教程。
      # 此外，Nixpkgs 模块系统还有一种方式来带参数地引入其他文件：
      #   该文件必须是一个返回值为属性集的函数，在 imports = [ ... ]; 内使用括号包裹的 import 原语，形式如下：
      #     imports = [ (import ./a.nix { b = "c"; }) ];
      #   或 flakes 组织的 NixOS 配置的 modules 列表中：
      #     modules = [ (import ./a.nix { b = "c"; }) ];
      #   这个方式携带的参数只有被调用的文件内可以使用，
      #   并且被引入的文件中也不可以使用 lib 、 config 这类由模块系统的自动注入的参数
      #   原因是这个文件并不是被当作模块对待的，尽管从文件内容的形式上看它可能完全符合模块的要求，
      #   但在这种调用方式下，括号内的表达式会被立即评估，是的，原语不是惰性求值的。那么具体过程是这样的：
      #   以路径 ./a.nix 为参数调用 imports 函数，返回./a.nix 中定义的函数，然后以 { b = "c"; } 为参数调用该函数，
      #   返回一个属性集，接下来的处理过程就和直接写在 imports 列表里的内联属性集一样了，
      #   所谓内联属性集就是我们常见的以下形式：
      #     imports = [ { a = b; } ];
      #   和：
      #     modules = [ { a = b; } ];
      #   一个单纯的属性集没有能接受参数的结构，模块系统无法对其注入，所以只能在其中进行 config 的定义，
      #   它适合简单、局部的配置定义，写起来比较方便
      specialArgs = {
        inherit inputs self;
        primaryDiskWwid = "ata-WDC_WD1600BEVT-22ZCT0_WD-WXC908420123";
        swapSize = "8G";
      };
      modules = [
        # > Our main nixos configuration file <
        ./Server-Ideapad-G480
      ];
    };
    Desktop-DIY-B650 = nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit inputs self;
        primaryDiskWwid = "ata-WDC_PC_SN520_SDAPNUW-512G_19529C801253";
        swapSize = "16G";
      };
      modules = [
        # > Our main nixos configuration file <
        ./Desktop-DIY-B650
      ];
    };
    Laptop-Legion-R7000 = nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit inputs self;
        primaryDiskWwid = "nvme-SAMSUNG_MZVLB512HBJQ-000L2_S4DYNF0N449629";
        swapSize = "16G";
      };
      modules = [
        # > Our main nixos configuration file <
        ./Laptop-Legion-R7000
      ];
    };
  };
}
