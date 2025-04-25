{ inputs, ... }:
{
  imports = [ inputs.vaultix.nixosModules.default ];
  services.userborn.enable = true;
  vaultix = {
    secrets = {
      root-password = {
        file = ../../../secrets/root-password.age;
        mode = "640"; # default 0400
        owner = "root";
        group = "users";
      };
      curious-password = {
        file = ../../../secrets/curious-password.age;
        mode = "640"; # default 0400
        owner = "root";
        group = "users";
      };
    };
    beforeUserborn = [
      "root-password"
      "curious-password"
    ];
  };
}
