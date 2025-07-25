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
        file = ../../../secrets/nixos/generic/core/root-password.age;
        mode = "640"; # default 0400
        owner = "root";
        group = "users";
      };
      curious-password = {
        file = ../../../secrets/nixos/generic/core/curious-password.age;
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
