{ pkgs, ... }:
{
  # Use the systemd-boot EFI boot loader.
  boot = {
    kernelPackages = pkgs.linuxPackages;
    loader = {
      systemd-boot.enable = true;
      systemd-boot.consoleMode = "auto";
      efi.canTouchEfiVariables = true;
    };
  };
}
