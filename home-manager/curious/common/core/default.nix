{ ... }:
{
  imports = [
    ./nix.nix
    ./vcs.nix
    ./cli-tools.nix
    ./yubico
  ];
  home = {
    username = "curious";
    homeDirectory = "/home/curious";
  };
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
