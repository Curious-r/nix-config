{
  overlays,
  pkgs,
  ...
}:
{
  imports = [
    ./boot.nix
    ./locale.nix # localization settings
    ./nix.nix # nix settings and garbage collection
    ./vaultix.nix # secrets management
    ./git.nix
    ./account.nix
    ./security
    ./console.nix
    ./fonts.nix
    ./editor.nix
    ./ssh.nix
    ./networking.nix
    ./preservation.nix
    ./home-manager.nix
    ./udisks2.nix
  ];

  nixpkgs = {
    # You can add global overlays here.
    overlays = builtins.attrValues overlays;
    config = {
      allowUnfree = true;
    };
  };

  # Enable all unfree hardware support.
  hardware.firmware = [ pkgs.linux-firmware ];
  hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;
}
