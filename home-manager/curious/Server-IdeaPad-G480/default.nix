{ ... }:
{
  imports = [
    ../common/core
    ../common/optional/nix/substituters/mainland.nix
    ../common/optional/nix/substituters/numtide.nix

    # XDG ENV
    ../common/optional/xdg-env/basic.nix
    ../common/optional/xdg-env/nvidia.nix
    ../common/optional/xdg-env/npm.nix

    ../common/optional/bash.nix
  ];
  home.stateVersion = "26.05";
}
