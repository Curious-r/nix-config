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
  #    Both bootloaders remain enabled, but evaluating the complete system configuration and
  #    bootloader installer fails because only one bootloader can be enabled at a time.
  case4 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.grub.enable = true;
    }
  ];
  testCase4 =
    let
      toplevelEval = builtins.tryEval case4.config.system.build.toplevel;
      installBootLoaderEval = builtins.tryEval case4.config.system.build.installBootLoader;
    in
    assert case4.config.boot.loader.sprout.enable == true;
    assert case4.config.boot.loader.grub.enable == true;
    assert toplevelEval.success == false;
    assert installBootLoaderEval.success == false;
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

  # 9. Sprout enabled, negative timeout:
  #    evaluating the NixOS system build assertion path rejects the configuration,
  #    and the failed assertion identifies boot.loader.timeout.
  case9 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.timeout = -1;
    }
  ];
  testCase9 =
    let
      toplevelEval = builtins.tryEval case9.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "boot.loader.timeout" x.message
      ) case9.config.assertions;
    in
    assert toplevelEval.success == false;
    assert failedAssertions != [ ];
    true;

  # 10. Sprout enabled, zero timeout:
  #     evaluating the NixOS system build assertion path accepts the configuration.
  case10 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.timeout = 0;
    }
  ];
  testCase10 =
    let
      toplevelEval = builtins.tryEval case10.config.system.build.toplevel;
      timeoutFailedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "boot.loader.timeout" x.message
      ) case10.config.assertions;
    in
    assert toplevelEval.success == true;
    assert timeoutFailedAssertions == [ ];
    true;

  # 11. Sprout enabled, positive timeout:
  #     evaluating the NixOS system build assertion path accepts the configuration.
  case11 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.timeout = 10;
    }
  ];
  testCase11 =
    let
      toplevelEval = builtins.tryEval case11.config.system.build.toplevel;
      timeoutFailedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "boot.loader.timeout" x.message
      ) case11.config.assertions;
    in
    assert toplevelEval.success == true;
    assert timeoutFailedAssertions == [ ];
    true;

  # 12. Sprout enabled, EFI Stub kernel requirement:
  #     system.requiredKernelConfig contains structured metadata with configLine "CONFIG_EFI_STUB=y".
  case12 = eval [ { boot.loader.sprout.enable = true; } ];
  testCase12 =
    let
      hasEfiStub = pkgs.lib.any (
        req: req.configLine == "CONFIG_EFI_STUB=y"
      ) case12.config.system.requiredKernelConfig;
      disabledHasEfiStub = pkgs.lib.any (
        req: req.configLine == "CONFIG_EFI_STUB=y"
      ) case2.config.system.requiredKernelConfig;
    in
    assert hasEfiStub;
    assert !disabledHasEfiStub;
    true;

  # 13. Sprout enabled, null timeout:
  #     evaluating the NixOS system build assertion path rejects the configuration,
  #     and the failed assertion identifies boot.loader.timeout and explains that null
  #     (an indefinitely displayed boot menu) is unsupported.
  case13 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.timeout = null;
    }
  ];
  testCase13 =
    let
      toplevelEval = builtins.tryEval case13.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x:
        !x.assertion
        && pkgs.lib.hasInfix "boot.loader.timeout" x.message
        && pkgs.lib.hasInfix "null" x.message
      ) case13.config.assertions;
    in
    assert toplevelEval.success == false;
    assert failedAssertions != [ ];
    true;

  # 14. Sprout enabled, systemd-boot explicitly enabled:
  #     both enable flags remain true, but evaluating the complete system configuration and
  #     bootloader installer fails because only one bootloader can be enabled at a time.
  case14 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.systemd-boot.enable = true;
    }
  ];
  testCase14 =
    let
      toplevelEval = builtins.tryEval case14.config.system.build.toplevel;
      installBootLoaderEval = builtins.tryEval case14.config.system.build.installBootLoader;
    in
    assert case14.config.boot.loader.sprout.enable == true;
    assert case14.config.boot.loader.systemd-boot.enable == true;
    assert toplevelEval.success == false;
    assert installBootLoaderEval.success == false;
    true;

  # 15. Sprout enabled, canTouchEfiVariables = false, efiInstallAsRemovable unset:
  #     efiInstallAsRemovable defaults to true, and the complete system configuration evaluates successfully.
  case15 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.efi.canTouchEfiVariables = false;
    }
  ];
  testCase15 =
    let
      toplevelEval = builtins.tryEval case15.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "boot.loader.sprout.efiInstallAsRemovable" x.message
      ) case15.config.assertions;
    in
    assert case15.config.boot.loader.sprout.efiInstallAsRemovable == true;
    assert toplevelEval.success == true;
    assert failedAssertions == [ ];
    true;

  # 16. Sprout enabled, canTouchEfiVariables = false, efiInstallAsRemovable = false:
  #     evaluating the complete system configuration fails, and the failed assertion
  #     identifies the removable fallback requirement.
  case16 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.efi.canTouchEfiVariables = false;
      boot.loader.sprout.efiInstallAsRemovable = false;
    }
  ];
  testCase16 =
    let
      toplevelEval = builtins.tryEval case16.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "boot.loader.sprout.efiInstallAsRemovable" x.message
      ) case16.config.assertions;
    in
    assert case16.config.boot.loader.sprout.efiInstallAsRemovable == false;
    assert toplevelEval.success == false;
    assert failedAssertions != [ ];
    true;

  # 17. Sprout enabled, canTouchEfiVariables = true, efiInstallAsRemovable unset:
  #     efiInstallAsRemovable defaults to false, and the complete system configuration evaluates successfully.
  case17 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
    }
  ];
  testCase17 =
    let
      toplevelEval = builtins.tryEval case17.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "boot.loader.sprout.efiInstallAsRemovable" x.message
      ) case17.config.assertions;
    in
    assert case17.config.boot.loader.sprout.efiInstallAsRemovable == false;
    assert toplevelEval.success == true;
    assert failedAssertions == [ ];
    true;

  # 18. Sprout enabled, default settings:
  #     entries, actions are empty and menu-style is null.
  case18 = eval [ { boot.loader.sprout.enable = true; } ];
  testCase18 =
    assert case18.config.boot.loader.sprout.settings.entries == { };
    assert case18.config.boot.loader.sprout.settings.actions == { };
    assert case18.config.boot.loader.sprout.settings.options.menu-style == null;
    true;

  # 19. Sprout enabled, valid static settings with menu-style, custom entry, and chainload action:
  #     evaluates successfully.
  case19 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings = {
        options.menu-style = "simple";
        entries.uefi-shell = {
          title = "UEFI Shell";
          actions = [ "uefi-shell" ];
          sort-key = "z-uefi-shell";
        };
        actions.uefi-shell.chainload = {
          path = "\\EFI\\tools\\Shell.efi";
        };
      };
    }
  ];
  testCase19 =
    let
      toplevelEval = builtins.tryEval case19.config.system.build.toplevel;
      installerEval = builtins.tryEval case19.config.system.build.installBootLoader.drvPath;
    in
    assert toplevelEval.success == true;
    assert installerEval.success == true;
    assert case19.config.boot.loader.sprout.settings.options.menu-style == "simple";
    assert case19.config.boot.loader.sprout.settings.entries.uefi-shell.title == "UEFI Shell";
    true;

  # 20. Sprout enabled, valid print and edera action variants:
  #     evaluates successfully.
  case20 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings = {
        entries = {
          pr-entry = {
            title = "Print Entry";
            actions = [ "pr-action" ];
          };
          ed-entry = {
            title = "Edera Entry";
            actions = [ "ed-action" ];
          };
        };
        actions = {
          pr-action.print = {
            text = "Welcome to Sprout";
          };
          ed-action.edera = {
            xen = "\\EFI\\xen.efi";
            kernel = "\\EFI\\vmlinuz";
            initrd = "\\EFI\\initrd.img";
            kernel-options = [ "console=tty0" ];
            xen-options = [ "dom0_mem=512M" ];
          };
        };
      };
    }
  ];
  testCase20 =
    let
      toplevelEval = builtins.tryEval case20.config.system.build.toplevel;
      installerEval = builtins.tryEval case20.config.system.build.installBootLoader.drvPath;
    in
    assert toplevelEval.success == true;
    assert installerEval.success == true;
    true;

  # 21. Sprout enabled, invalid menu-style:
  #     rejected by enum type check.
  case21 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings.options.menu-style = "invalid-style";
    }
  ];
  testCase21 =
    let
      installerEval = builtins.tryEval case21.config.system.build.installBootLoader.drvPath;
    in
    assert installerEval.success == false;
    true;

  # 22. Sprout enabled, entry missing title:
  #     rejected because title is required.
  case22 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings = {
        entries.no-title = {
          actions = [ "some-action" ];
        };
        actions.some-action.print.text = "hi";
      };
    }
  ];
  testCase22 =
    let
      installerEval = builtins.tryEval case22.config.system.build.installBootLoader.drvPath;
    in
    assert installerEval.success == false;
    true;

  # 23. Sprout enabled, entry with empty actions list:
  #     rejected by assertion.
  case23 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings.entries.no-actions = {
        title = "No Actions";
        actions = [ ];
      };
    }
  ];
  testCase23 =
    let
      toplevelEval = builtins.tryEval case23.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "actions must be non-empty" x.message
      ) case23.config.assertions;
    in
    assert toplevelEval.success == false;
    assert failedAssertions != [ ];
    true;

  # 24. Sprout enabled, action declaring zero variants:
  #     rejected by assertion.
  case24 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings.actions.zero-variant = { };
    }
  ];
  testCase24 =
    let
      toplevelEval = builtins.tryEval case24.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "must define exactly one variant" x.message
      ) case24.config.assertions;
    in
    assert toplevelEval.success == false;
    assert failedAssertions != [ ];
    true;

  # 25. Sprout enabled, action declaring multiple variants:
  #     rejected by assertion.
  case25 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings.actions.multi-variant = {
        chainload.path = "\\EFI\\boot.efi";
        print.text = "also print";
      };
    }
  ];
  testCase25 =
    let
      toplevelEval = builtins.tryEval case25.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "must define exactly one variant" x.message
      ) case25.config.assertions;
    in
    assert toplevelEval.success == false;
    assert failedAssertions != [ ];
    true;

  # 26. Sprout enabled, chainload specifying both linux-initrd and linux-initrd-chain:
  #     rejected by assertion.
  case26 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings.actions.conflict-chain = {
        chainload = {
          path = "\\EFI\\kernel.efi";
          linux-initrd = "\\EFI\\initrd.img";
          linux-initrd-chain = [ "\\EFI\\initrd2.img" ];
        };
      };
    }
  ];
  testCase26 =
    let
      toplevelEval = builtins.tryEval case26.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x:
        !x.assertion
        && pkgs.lib.hasInfix "cannot specify both 'linux-initrd' and 'linux-initrd-chain'" x.message
      ) case26.config.assertions;
    in
    assert toplevelEval.success == false;
    assert failedAssertions != [ ];
    true;

  # 27. Sprout enabled, edera specifying both initrd and initrd-chain:
  #     rejected by assertion.
  case27 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings.actions.conflict-edera = {
        edera = {
          xen = "\\EFI\\xen.efi";
          kernel = "\\EFI\\vmlinuz";
          initrd = "\\EFI\\initrd.img";
          initrd-chain = [ "\\EFI\\initrd2.img" ];
        };
      };
    }
  ];
  testCase27 =
    let
      toplevelEval = builtins.tryEval case27.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "cannot specify both 'initrd' and 'initrd-chain'" x.message
      ) case27.config.assertions;
    in
    assert toplevelEval.success == false;
    assert failedAssertions != [ ];
    true;

  # 28. Sprout enabled, unknown setting field:
  #     rejected by submodule schema.
  case28 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings.unknownOption = 42;
    }
  ];
  testCase28 =
    let
      installerEval = builtins.tryEval case28.config.system.build.installBootLoader.drvPath;
    in
    assert installerEval.success == false;
    true;

  # 29. Sprout enabled, settings cannot set module-owned menu-timeout:
  #     rejected by options submodule schema.
  case29 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings.options.menu-timeout = 10;
    }
  ];
  testCase29 =
    let
      installerEval = builtins.tryEval case29.config.system.build.installBootLoader.drvPath;
    in
    assert installerEval.success == false;
    true;

  # 30. Sprout enabled, settings cannot set module-owned drivers:
  #     rejected by settings submodule schema.
  case30 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings.drivers = { };
    }
  ];
  testCase30 =
    let
      installerEval = builtins.tryEval case30.config.system.build.installBootLoader.drvPath;
    in
    assert installerEval.success == false;
    true;

  # 31. Sprout enabled, empty entry name:
  #     rejected by assertion.
  case31 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings = {
        entries."" = {
          title = "Empty Name";
          actions = [ "act" ];
        };
        actions.act.print.text = "hello";
      };
    }
  ];
  testCase31 =
    let
      toplevelEval = builtins.tryEval case31.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "cannot contain an empty entry name" x.message
      ) case31.config.assertions;
    in
    assert toplevelEval.success == false;
    assert failedAssertions != [ ];
    true;

  # 32. Sprout enabled, reserved nixos- prefix on entry:
  #     rejected by assertion.
  case32 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings = {
        entries.nixos-custom = {
          title = "Reserved Prefix";
          actions = [ "action1" ];
        };
        actions.action1.print.text = "hello";
      };
    }
  ];
  testCase32 =
    let
      toplevelEval = builtins.tryEval case32.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "cannot use reserved 'nixos-' prefix" x.message
      ) case32.config.assertions;
    in
    assert toplevelEval.success == false;
    assert failedAssertions != [ ];
    true;

  # 33. Sprout enabled, entry referencing nonexistent action:
  #     rejected by assertion.
  case33 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings = {
        entries.custom = {
          title = "Custom";
          actions = [ "missing-action" ];
        };
        actions = { };
      };
    }
  ];
  testCase33 =
    let
      toplevelEval = builtins.tryEval case33.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "must exist in boot.loader.sprout.settings.actions" x.message
      ) case33.config.assertions;
    in
    assert toplevelEval.success == false;
    assert failedAssertions != [ ];
    true;

  # 34. Sprout enabled, edera action missing required kernel:
  #     rejected because kernel is required.
  case34 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings.actions.bad-edera.edera = {
        xen = "\\EFI\\xen.efi";
      };
    }
  ];
  testCase34 =
    let
      installerEval = builtins.tryEval case34.config.system.build.installBootLoader.drvPath;
    in
    assert installerEval.success == false;
    true;

  # 35. Sprout enabled, settings cannot set module-owned default-entry:
  #     rejected by options submodule schema.
  case35 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings.options.default-entry = "custom";
    }
  ];
  testCase35 =
    let
      installerEval = builtins.tryEval case35.config.system.build.installBootLoader.drvPath;
    in
    assert installerEval.success == false;
    true;

  # 36. Sprout enabled, empty action name:
  #     rejected by assertion.
  case36 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings.actions."" = {
        print.text = "hello";
      };
    }
  ];
  testCase36 =
    let
      toplevelEval = builtins.tryEval case36.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "cannot contain an empty action name" x.message
      ) case36.config.assertions;
    in
    assert toplevelEval.success == false;
    assert failedAssertions != [ ];
    true;

  # 37. Sprout enabled, reserved nixos- prefix on action:
  #     rejected by assertion.
  case37 = eval [
    {
      boot.loader.sprout.enable = true;
      boot.loader.sprout.settings.actions.nixos-custom = {
        print.text = "hello";
      };
    }
  ];
  testCase37 =
    let
      toplevelEval = builtins.tryEval case37.config.system.build.toplevel;
      failedAssertions = builtins.filter (
        x: !x.assertion && pkgs.lib.hasInfix "cannot use reserved 'nixos-' prefix" x.message
      ) case37.config.assertions;
    in
    assert toplevelEval.success == false;
    assert failedAssertions != [ ];
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
assert testCase9;
assert testCase10;
assert testCase11;
assert testCase12;
assert testCase13;
assert testCase14;
assert testCase15;
assert testCase16;
assert testCase17;
assert testCase18;
assert testCase19;
assert testCase20;
assert testCase21;
assert testCase22;
assert testCase23;
assert testCase24;
assert testCase25;
assert testCase26;
assert testCase27;
assert testCase28;
assert testCase29;
assert testCase30;
assert testCase31;
assert testCase32;
assert testCase33;
assert testCase34;
assert testCase35;
assert testCase36;
assert testCase37;
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
    testCase9
    testCase10
    testCase11
    testCase12
    testCase13
    testCase14
    testCase15
    testCase16
    testCase17
    testCase18
    testCase19
    testCase20
    testCase21
    testCase22
    testCase23
    testCase24
    testCase25
    testCase26
    testCase27
    testCase28
    testCase29
    testCase30
    testCase31
    testCase32
    testCase33
    testCase34
    testCase35
    testCase36
    testCase37
    ;
}
