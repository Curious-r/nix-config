{ inputs, ... }:
{
  imports = [
    inputs.impermanence.nixosModules.impermanence
    ./global.nix
    ./curious.nix
  ];
}
