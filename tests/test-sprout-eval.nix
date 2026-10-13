let
  sources = import ../npins;
  pkgs = import sources.nixpkgs { };

  evalNixos = import "${sources.nixpkgs}/nixos/lib/eval-config.nix";

  # Placeholder Sprout package satisfying types.package and providing lib/sprout/sprout.efi
  # without building or executing a real EFI binary.
  placeholderSprout = pkgs.runCommand "sprout-placeholder" { } ''
    mkdir -p $out/lib/sprout
    touch $out/lib/sprout/sprout.efi
  '';

  eval =
    extraModules:
    evalNixos {
      system = "x86_64-linux";
      modules = [
        ../modules/nixos/sprout.nix
        {
          boot.loader.sprout.package = placeholderSprout;
          fileSystems."/".device = "/dev/dummy";
        }
      ]
      ++ extraModules;
    };

  # 1. Sprout enabled, GRUB unspecified:
  #    boot.loader.grub.enable evaluates to false, and system.boot.loader.id evaluates to "sprout".
  case1 = eval [ { boot.loader.sprout.enable = true; } ];
  testCase1 =
    assert case1.config.boot.loader.grub.enable == false;
    assert case1.config.system.boot.loader.id == "sprout";
    true;

  # 2. Sprout disabled, GRUB unspecified:
  #    the existing GRUB default remains unchanged for a normal non-container NixOS configuration.
  case2 = eval [ { boot.loader.sprout.enable = false; } ];
  testCase2 =
    assert case2.config.boot.loader.grub.enable == true;
    assert case2.config.system.boot.loader.id == "grub";
    true;

  # 3. Sprout enabled, GRUB explicitly disabled:
  #    GRUB remains disabled.
  case3 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.grub.enable = false;
    }
  ];
  testCase3 =
    assert case3.config.boot.loader.grub.enable == false;
    assert case3.config.system.boot.loader.id == "sprout";
    true;

  # 4. Sprout enabled, GRUB explicitly enabled:
  #    the explicit boot.loader.grub.enable = true definition is not silently overridden by Sprout's default.
  #    Do not force GRUB off to conceal a conflicting bootloader selection.
  case4 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.grub.enable = true;
    }
  ];
  testCase4 =
    assert case4.config.boot.loader.grub.enable == true;
    true;
in
assert testCase1;
assert testCase2;
assert testCase3;
assert testCase4;
{
  inherit
    testCase1
    testCase2
    testCase3
    testCase4
    ;
}
