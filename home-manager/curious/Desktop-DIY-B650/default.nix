{ ... }:
{
  imports = [
    ../generic/core
    ../generic/optional/nix/substituters/mainland.nix
    ../generic/optional/zed-editor.nix
    ../generic/optional/firefox.nix
  ];
  home.stateVersion = "25.05";
}
