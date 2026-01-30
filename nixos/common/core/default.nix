{
  self,
  pkgs,
  ...
}:
{
  imports = [
    ./boot.nix
    ./locale.nix # localization settings
    ./nix.nix # nix settings and garbage collection
    ./git.nix # git 被 nix flakes 强依赖，devenv 也用得到
    ./vaultix.nix # secrets management
    ./users.nix
    ./security.nix
    ./console.nix
    ./editor.nix
    ./ssh.nix
    ./networking.nix
    ./file-manager.nix
    ./preservation.nix
    ./home-manager.nix
    ./devenv.nix
  ];

  nixpkgs = {
    # you can add global overlays here
    overlays = builtins.attrValues self.overlays;
    config = {
      allowUnfree = true;
    };
  };

  # Enable all unfree hardware support.
  hardware.firmware = with pkgs; [ linux-firmware ];
  hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;
}
