{ ... }:
{
  # Use the systemd-boot EFI boot loader.
  boot = {
    loader = {
      systemd-boot.enable = true;
      systemd-boot.consoleMode = "auto";
      efi.canTouchEfiVariables = true;
    };

    kernelParams = [ "video=1366x768@60" ];
  };
}
