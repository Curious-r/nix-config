{ ... }:
{
  imports = [
    ../common/core
    ../common/optional/nix/substituters/mainland.nix
  ];
  home.stateVersion = "25.05";
}
