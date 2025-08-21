{ pkgs, ... }:
{
  programs = {
    git = {
      enable = true;
      userName = "Curious";
      userEmail = "Curious@curious.host";
    };
  };
}
