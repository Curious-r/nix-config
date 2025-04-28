{ inputs, ... }:
{
  imports = [ inputs.vaultix.nixosModules.default ];
  services.userborn.enable = true;
  services.openssh.hostKeys = [
    {
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  vaultix = {
    secrets = {
      root-password = {
        file = ../../../secrets/root-password.age;
        mode = "640"; # default 0400
        owner = "root";
        group = "users";
        path = "/var/lib/vaultix/root-password";
      };
      curious-password = {
        file = ../../../secrets/curious-password.age;
        mode = "640"; # default 0400
        owner = "root";
        group = "users";
        path = "/var/lib/vaultix/curious-password";
      };
    };
    beforeUserborn = [
    "root-password"
    "curious-password"
    ];
  };
}
