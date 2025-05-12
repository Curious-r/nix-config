{ ... }:
{
  imports = [
    ./nix.nix
    ./editor.nix
    ./git.nix
    ./cli-tools.nix
  ];
  home.username = "curious";
  home.homeDirectory = "/home/curious";
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
