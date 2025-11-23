{ ... }:
{
  imports = [
    ../generic/core
    ../generic/optional/nix/substituters/mainland.nix
    ../generic/optional/desktop.nix
    ../generic/optional/rime
    ../generic/optional/zed-editor.nix
    ../generic/optional/browser/zen.nix
    ../generic/optional/browser/servo.nix
    ../generic/optional/thunderbird.nix
    ../generic/optional/openscad.nix
    # ../generic/optional/rclone.nix
  ];
  home.stateVersion = "25.05";
}
