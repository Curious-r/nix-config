{
  pkgs,
  inputs,
  ...
}:
{
  environment.packages = with pkgs; [
    inputs.helix.packages."${pkgs.system}".helix # or some other editor, e.g. nano or neovim
  ];
}
