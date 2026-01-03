{ ... }:
{
  programs.ghostty = {
    enable = true;
    settings = {
      theme = "Catppuccin Mocha";
      font-size = 12;
      font-family = "Monaspace Neon Var";
      font-feature = "calt, liga, ss01, ss02, ss03, ss04, ss05, ss06, ss07, ss08, ss09, ss10";
    };
    systemd.enable = true;
    enableBashIntegration = true;
  };
}
