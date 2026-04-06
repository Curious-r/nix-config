{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # 我们用的 UEFI 固件加 ACPI 表，这两个工具应该是用不了了。
    # libraspberrypi
    # raspberrypi-eeprom
  ];
}
