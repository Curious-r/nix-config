{
  pkgs,
  nixosModules,
  ...
}:
{
  imports = [ nixosModules.sprout ];

  boot = {
    loader = {
      systemd-boot.enable = false;
      efi.canTouchEfiVariables = true;
      timeout = null;

      sprout = {
        enable = true;
        package = pkgs.curious.sprout;
        configurationLimit = 20;
        efiInstallAsRemovable = false;
        settings = {
          options.menu-style = "graphical";
          menu-styles.graphical.enable-mouse = true;
        };
      };
    };
    # 用于为其他架构构建系统。
    binfmt = {
      emulatedSystems = [ "aarch64-linux" ];
      # Prefer static emulators when available, allowing binfmt registrations
      # to remain usable across chroots and mount namespaces.
      preferStaticEmulators = true;
    };
  };
}
