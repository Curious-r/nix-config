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
          system.stateVersion = "24.11";
          boot.loader.sprout.package = placeholderSprout;
          fileSystems."/".device = "/dev/dummy";
          fileSystems."/".fsType = "ext4";
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

  # 5. Sprout enabled, negative configurationLimit:
  #    evaluating the NixOS system build assertion path rejects the configuration.
  case5 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.configurationLimit = -1;
    }
  ];
  testCase5 =
    let
      toplevelEval = builtins.tryEval case5.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "boot.loader.sprout.configurationLimit" x.message
      ) case5.config.assertions;
    in
    assert toplevelEval.success == false;
    assert failedAssertions != [ ];
    true;

  # 6. Sprout enabled, default (null) configurationLimit:
  #    evaluating the NixOS system build assertion path accepts the configuration.
  case6 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.configurationLimit = null;
    }
  ];
  testCase6 =
    let
      toplevelEval = builtins.tryEval case6.config.system.build.toplevel;
      sproutFailedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "boot.loader.sprout.configurationLimit" x.message
      ) case6.config.assertions;
    in
    assert toplevelEval.success == true;
    assert sproutFailedAssertions == [ ];
    true;

  # 7. Sprout enabled, zero configurationLimit:
  #    evaluating the NixOS system build assertion path accepts the configuration.
  case7 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.configurationLimit = 0;
    }
  ];
  testCase7 =
    let
      toplevelEval = builtins.tryEval case7.config.system.build.toplevel;
      sproutFailedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "boot.loader.sprout.configurationLimit" x.message
      ) case7.config.assertions;
    in
    assert toplevelEval.success == true;
    assert sproutFailedAssertions == [ ];
    true;

  # 8. Sprout enabled, positive configurationLimit:
  #    evaluating the NixOS system build assertion path accepts the configuration.
  case8 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.configurationLimit = 10;
    }
  ];
  testCase8 =
    let
      toplevelEval = builtins.tryEval case8.config.system.build.toplevel;
      sproutFailedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "boot.loader.sprout.configurationLimit" x.message
      ) case8.config.assertions;
    in
    assert toplevelEval.success == true;
    assert sproutFailedAssertions == [ ];
    true;
in
assert testCase1;
assert testCase2;
assert testCase3;
assert testCase4;
assert testCase5;
assert testCase6;
assert testCase7;
assert testCase8;
{
  inherit
    testCase1
    testCase2
    testCase3
    testCase4
    testCase5
    testCase6
    testCase7
    testCase8
    ;
}
