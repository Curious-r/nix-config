{ pkgs, ... }:
{
  home.packages = with pkgs; [ servo ];
}
