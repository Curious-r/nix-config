{ lib, inputs, ... }:
{
  imports = [
    inputs.impermanence.nixosModules.impermanence
    inputs.disko.nixosModules.disko
    ./global.nix
    ./curious.nix
  ];
}
