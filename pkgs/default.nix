# Custom packages that can be defined similarly to ones from nixpkgs.
# You can build them using 'nix build .#example'.
pkgs:
let
  # aerion-creds = pkgs.callPackage ./aerion-creds.nix { };
  cc-switch = pkgs.callPackage ./cc-switch.nix { };
in
{
  # example = pkgs.callPackage ./example { };

  # ======================================================================================
  # Aerion has been merged into nixpkgs. Keep it here as an example for packages with
  # an optional binary shim.
  # inherit aerion-creds;

  # `aerion-creds` is explicitly passed here (not relying on callPackage to find it in pkgs),
  # because aerion-creds is defined in this same set and may not be available in the pkgs
  # passed to this function — for example, a package set without this repository's overlay.
  # aerion = pkgs.callPackage ./aerion.nix { inherit aerion-creds; };
  # ======================================================================================

}
