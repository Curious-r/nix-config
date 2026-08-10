{ pkgs, ... }:
{
  boot = {
    plymouth = {
      enable = true;
      theme = "abstract_ring";
      themePackages = [
        # By default, we would install all themes.
        (pkgs.adi1090x-plymouth-themes.override {
          selected_themes = [ "abstract_ring" ];
        })
      ];
    };
  };
}
