{ ... }:
{
  # Use the systemd-boot EFI boot loader.
  boot = {
    loader = {
      systemd-boot.enable = true;
      systemd-boot.consoleMode = "auto";
      efi.canTouchEfiVariables = true;
    };
    # 用于为其他架构构建系统
    binfmt.emulatedSystems = [ "aarch64-linux" ];
  };
}
