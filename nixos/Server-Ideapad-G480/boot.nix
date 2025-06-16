{ ... }:
{
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.consoleMode = "auto";
  boot.loader.efi.canTouchEfiVariables = true;

  # 禁用烦人的bcm4313调试信息
  boot.consoleLogLevel = 3;

  boot.kernelParams = [ "video=1366x768@60" ];
}
