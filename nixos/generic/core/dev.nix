{ pkgs, ... }:
{
  programs = {
    direnv.enable = true;
  };
  environment.systemPackages = with pkgs; [
    devenv
  ];
}
