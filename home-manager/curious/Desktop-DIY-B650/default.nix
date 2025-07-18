{ ... }:
{
  imports = [
    ../generic/core
    ../generic/optional/nix/substituters/mainland.nix
    ../generic/optional/desktop.nix
    ../generic/optional/zed-editor.nix
    ../generic/optional/browser/firefox.nix
    ../generic/optional/browser/servo.nix
    ../generic/optional/thunderbird.nix
    ../generic/optional/rime
  ];
  home.stateVersion = "25.05";
}
