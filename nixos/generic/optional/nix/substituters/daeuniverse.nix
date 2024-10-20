{ ... }:
{
  nix = {
    settings = {

      substituters = [ "https://daeuniverse.cachix.org" ];

      trusted-public-keys = [ "daeuniverse.cachix.org-1:8hRIzkQmAKxeuYY3c/W1I7QbZimYphiPX/E7epYNTeM=" ];
    };
  };
}
