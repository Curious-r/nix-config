{ pkgs, ... }:
{
  programs = {
    git = {
      enable = true;
      userName = "Curious";
      userEmail = "Curious@curious.host";
    };
  };
  home.packages = with pkgs; [ pijul ];
}
