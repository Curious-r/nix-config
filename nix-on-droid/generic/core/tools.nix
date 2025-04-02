{
  pkgs,
  ...
}:
{
  environment.packages = with pkgs; [
    helix # or some other editor, e.g. nano or neovim
    git
    openssh
    curl
  ];
}
