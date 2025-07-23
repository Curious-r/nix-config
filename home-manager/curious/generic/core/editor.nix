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
      language = [
        {
          name = "nix";
          auto-format = true;
          language-servers = [ "nixd" ];
        }
      ];
      language-server = {
        nixd = {
          command = "nixd";
          args = [ "--semantic-tokens=true" ];
          config.nixd = {
            formatting.command = [ "nixfmt" ];
          };
        };
      };
    };
  };
}
