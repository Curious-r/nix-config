{ ... }:
{
  imports = [
    ./nix.nix
    ./dev.nix
    ./cli-tools.nix
  ];
  home = {
    username = "curious";
    homeDirectory = "/home/curious";
  };
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
