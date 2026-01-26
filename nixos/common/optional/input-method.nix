{
  pkgs,
  ...
}:
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-material-color # a color theme
      (fcitx5-rime.override {
        rimeDataPkgs = [ rime-wanxiang ];
      })
    ];
  };
}
