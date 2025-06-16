{ ... }:
{
  imports = [
    ../generic/core
    ../generic/optional/nix/substituters/mainland.nix
    ../generic/optional/zed-editor.nix
    ../generic/optional/firefox.nix
    ../generic/optional/rime
  ];
  home.stateVersion = "25.05";
}
