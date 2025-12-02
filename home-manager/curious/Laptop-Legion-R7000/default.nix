{ ... }:
{
  imports = [
    ../generic/core
    ../generic/optional/nix/substituters/mainland.nix
    ../generic/optional/desktop.nix
    ../generic/optional/rime
    ../generic/optional/terminal/ghostty.nix
    ../generic/optional/editor/zed.nix
    ../generic/optional/browser/zen.nix
    ../generic/optional/browser/servo.nix
    ../generic/optional/thunderbird.nix
    ../generic/optional/openscad.nix
    # ../generic/optional/rclone.nix
  ];
  home.stateVersion = "26.05";
}
