{ pkgs, self, ... }:
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-gtk # alternatively, kdePackages.fcitx5-qt
      fcitx5-material-color # a color theme
      (unstable.fcitx5-rime.override {
        rimeDataPkgs = [
          self.packages.${pkgs.system}.rime-wanxiang
          # unstable.rime-wanxiang
        ];
      })
    ];
  };
}
