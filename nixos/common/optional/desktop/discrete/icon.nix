{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.papirus-icon-theme
    # 必装的基础包，防止图标回退时出现方块
    pkgs.adwaita-icon-theme
    pkgs.hicolor-icon-theme
  ];
}
