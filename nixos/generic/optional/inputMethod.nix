{ pkgs, lib, ... }:
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-gtk # alternatively, kdePackages.fcitx5-qt
      fcitx5-nord # a color theme
      fcitx5-rime
    ];
  };
}
