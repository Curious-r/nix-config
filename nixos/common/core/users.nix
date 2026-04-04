{ config, ... }:
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
        ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvTmb1zsdEywosctFd+5dlXM3fgKIeK5xzCZp0WtR1b curious"
        ];
      };
    };
  };
}
