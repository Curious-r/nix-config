{ ... }:
{
  imports = [
    ./nix.nix
    ./vcs
    ./devenv.nix
    ./zellij.nix
    ./rg.nix
  ];
  home = {
    username = "curious";
    homeDirectory = "/home/curious";
  };
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
