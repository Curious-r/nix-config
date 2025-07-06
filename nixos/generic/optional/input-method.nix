{ pkgs, ... }:
{

  nixpkgs.overlays = [
    (final: prev: {
      librime =
        (prev.librime.override {
          plugins = [
            pkgs.librime-lua
            pkgs.librime-octagram
          ];
        }).overrideAttrs
          (old: {
            buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.luajit ]; # 用luajit
            #         buildInputs = (old.buildInputs or []) ++ [pkgs.lua5_4]; # 用lua5.4
          });
    })
  ];

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-gtk # alternatively, kdePackages.fcitx5-qt
      fcitx5-material-color # a color theme
      (fcitx5-rime.override {
        rimeDataPkgs = [
          rime-data
          rime-wanxiang
        ];
      })
    ];
  };
}
