{ ... }:
{
  programs.ghostty = {
    enable = true;
    settings = {
      theme = "light:One Half Light,dark:One Half Dark";

      background-opacity = 0.85;
      background-blur-radius = 20;

      font-size = 12;
      font-family = "Monaspace Neon Var";
      font-feature = "calt, liga, ss01, ss02, ss03, ss04, ss05, ss06, ss07, ss08, ss09, ss10";

      shell-integration-features = "cursor, sudo, title, ssh-terminfo, ssh-env";
    };

    systemd.enable = true;
    enableBashIntegration = true;
  };
}
