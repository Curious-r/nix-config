# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs:
let
  # aerion-creds = pkgs.callPackage ./aerion-creds.nix { };
in
{
  # example = pkgs.callPackage ./example { };

  # ======================================================================================
  # Aerion has been merged into nixpkgs, keep it there to be a example for packages with
  # optianal binary shim
  # inherit aerion-creds;

  # `aerion-creds` is explicitly passed here (not relying on callPackage to find it in pkgs),
  # because aerion-creds is defined in this same set and may not be available in the pkgs
  # passed to this function — e.g. when called from perSystem (flake-parts) where custom
  # overlays aren't automatically applied
  # aerion = pkgs.callPackage ./aerion.nix { inherit aerion-creds; };
  # ======================================================================================
}
