{ pkgs, ... }:
{
  programs = {
    git = {
      enable = true;
      settings = {
        user = {
          name = "Curious";
          email = "Curious@curious.host";
        };
      };
    };
  };
  home.packages = with pkgs; [ pijul ];
}
