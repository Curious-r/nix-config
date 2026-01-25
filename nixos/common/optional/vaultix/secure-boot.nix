{ ... }:
{
  vaultix.secrets = {
    "db.key" = {
      file = ../../../../secrets/nixos/generic/optional/db.key.age;
      mode = "400";
      owner = "root";
      group = "root";
    };
    "db.pem" = {
      file = ../../../../secrets/nixos/generic/optional/db.pem.age;
      mode = "400";
      owner = "root";
      group = "root";
    };
  };
}
