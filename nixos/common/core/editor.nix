{ pkgs, ... }:
{
  programs.nano.enable = false;
  environment = {
    variables.EDITOR = "hx";
    systemPackages = [
      # Do not forget to add an editor for editing configuration.nix! The Nano editor is also installed by default.
      pkgs.helix
    ];
  };
}
