{ pkgs, config, ... }:
{
  users = {
    mutableUsers = false;
    users = {
      root = {
        hashedPasswordFile = config.vaultix.secrets.root-password.path;
      };

      curious = {
        isNormalUser = true;
        description = "Curious";
        hashedPasswordFile = config.vaultix.secrets.curious-password.path;
        extraGroups = [
          "wheel" # Enable ‘sudo’ for the user.
          "networkmanager"
        ];
      };
    };
  };

  security.sudo-rs = {
    enable = true;
    wheelNeedsPassword = false;
  };
}
