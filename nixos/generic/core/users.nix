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
          "wheel"
          "networkmanager"
        ]; # Enable ‘sudo’ for the user.
      };
    };
  };

  security.sudo-rs = {
    enable = true;
    wheelNeedsPassword = false;
  };
}
