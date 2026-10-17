{ nixosModules, pkgs, ... }:
{
  imports = [ nixosModules.sprout ];

  boot = {
    loader = {
      systemd-boot.enable = false;
      efi.canTouchEfiVariables = true;
      timeout = 5;

      sprout = {
        enable = true;
        package = pkgs.curious.sprout;
        configurationLimit = 3;
        efiInstallAsRemovable = false;
      };
    };
    # 用于为其他架构构建系统。
    binfmt.emulatedSystems = [ "aarch64-linux" ];
  };
}
