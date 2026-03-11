{ pkgs, ... }:
{
  home.packages = with pkgs; [ pijul ];
}
