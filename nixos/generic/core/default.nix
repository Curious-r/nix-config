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
    ./sops.nix # secrets management
    ./users.nix
    ./console.nix
    ./editor.nix
    ./ssh.nix
    ./networking.nix
  ];

  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=120 # only ask for password every 2h
    # Keep SSH_AUTH_SOCK so that pam_ssh_agent_auth.so can do its magic.
    # Defaults env_keep + =SSH_AUTH_SOCK
  '';

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
