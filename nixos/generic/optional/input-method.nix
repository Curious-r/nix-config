{
  pkgs,
  lib,
  config,
  ...
}:
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    package = lib.mkForce (
      pkgs.unstable.qt6Packages.fcitx5-with-addons.override {
        inherit (config.i18n.inputMethod.fcitx5) addons;
      }
    );
    fcitx5.addons = with pkgs; [
      fcitx5-gtk # alternatively, kdePackages.fcitx5-qt
      fcitx5-material-color # a color theme
      (unstable.fcitx5-rime.override {
        rimeDataPkgs = [
          unstable.rime-wanxiang
        ];
      })
    ];
  };
}
