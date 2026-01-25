{ ... }:
{
  imports = [
    ../common/core
    ../common/optional/nix/substituters/mainland.nix
    ../common/optional/desktop.nix
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
