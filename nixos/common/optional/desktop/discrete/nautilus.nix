{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.nautilus
  ];
}
