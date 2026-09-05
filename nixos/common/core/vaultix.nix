{
  pkgs,
  sources,
  thirdPartyPackages,
  ...
}:
let
  vaultixFlake = {
    _type = "flake";
    outPath = ../../..;
    vaultix = import ../../../secrets/vaultix.nix;
  };
in
{
  imports = [ "${sources.vaultix}/module" ];
  services.userborn.enable = true;
  services.openssh.hostKeys = [
    {
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  vaultix = {
    package = thirdPartyPackages.vaultix pkgs;
    settings.flake = vaultixFlake;
    secrets = {
      root-password = {
        file = ../../../secrets/nixos/common/core/root-password.age;
        mode = "640"; # default 0400
        owner = "root";
        group = "users";
      };
      curious-password = {
        file = ../../../secrets/nixos/common/core/curious-password.age;
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
