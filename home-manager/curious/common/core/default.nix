{ ... }:
{
  imports = [
    ./nix.nix
    ./vcs
    ./devenv.nix
    ./zellij.nix
    ./yazi.nix
  ];
  home = {
    username = "curious";
    homeDirectory = "/home/curious";
  };
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
