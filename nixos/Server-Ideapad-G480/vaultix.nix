{ ... }:
{
  vaultix = {
    settings = {
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIO/Jec53iGGzJTHHZ46iItwRJJ+I1KKgLmSfOObIUO6";
    };
    secrets = {
      "config.dae" = {
        file = ../../secrets/nixos/Server-Ideapad-G480/config.dae.age;
        mode = "640";
        owner = "root";
        group = "users";
      };
    };
  };
}
