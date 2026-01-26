{ ... }:
{
  imports = [
    ../common/core
    ../common/optional/nix/substituters/mainland.nix

    # Desktop
    ../common/optional/desktop/basic.nix
    ../common/optional/desktop/discrete/niri

    ../common/optional/rime
    ../common/optional/terminal/ghostty.nix
    ../common/optional/editor/zed.nix
    ../common/optional/browser/zen.nix
    ../common/optional/browser/servo.nix
    ../common/optional/thunderbird.nix
    ../common/optional/openscad.nix
    # ../common/optional/rclone.nix
  ];
  home.stateVersion = "26.05";
}
