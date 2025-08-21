{ pkgs, ... }:
{
  programs.nano.enable = false;
  environment = {
    variables.EDITOR = "hx";
    systemPackages = with pkgs; [
      # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
      helix
    ];
  };
}
