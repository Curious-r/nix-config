{ pkgs, config, ... }:
{
  sops.secrets = {
    "passwords/users/root".neededForUsers = true;
    "passwords/users/curious".neededForUsers = true;
  };

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
