{ ... }:
{
  vaultix = {
    settings = {
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIO/Jec53iGGzJTHHZ46iItwRJJ+I1KKgLmSfOObIUO6";
    };
    secrets = {
      dae-config = {
        file = ../../secrets/nixos/Server-Ideapad-G480/dae-config.age;
        mode = "640";
        owner = "root";
        name = "config.dae";
        group = "users";
      };
    };
  };
}
