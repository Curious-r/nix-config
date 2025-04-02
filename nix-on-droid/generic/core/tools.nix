{
  pkgs,
  ...
}:
{
  environment.packages = with pkgs; [
    helix # or some other editor, e.g. nano or neovim
    openssh
    curl
  ];
}
