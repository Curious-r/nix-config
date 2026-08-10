# Add your reusable NixOS modules to this directory, in their own file (https://nixos.wiki/wiki/Module).
# These should be things you would like to share with others, not your personal configurations.
{
  # List your module files here.
  # my-module = import ./my-module.nix;

  daed = import ./daed.nix;
  ddns-go = import ./ddns-go.nix;
}
