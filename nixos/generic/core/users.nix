{ config, ... }:
{
  users = {
    mutableUsers = false;
    users = {
      root = {
        hashedPasswordFile = config.sops.secrets."passwords/users/root".path;
      };

      curious = {
        isNormalUser = true;
        description = "Curious";
        hashedPasswordFile = config.sops.secrets."passwords/users/curious".path;
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
