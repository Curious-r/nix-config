{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    papirus-icon-theme
    # 必装的基础包，防止图标回退时出现方块
    adwaita-icon-theme
    hicolor-icon-theme
  ];
}
