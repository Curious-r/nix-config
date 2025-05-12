{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nixd
    nixfmt-rfc-style
  ];
  programs.helix = {
    enable = true;
    defaultEditor = true;
    languages = {
      language-server.nixd = {
        command = "nixd";
        formatting = {
          command = [ "nixfmt" ];
        };
      };
    };
  };
}
