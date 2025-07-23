{
  inputs,
  lib,
  config,
  ...
}:
{
  imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.lanzaboote = {
    enable = true;
    publicKeyFile = config.vaultix.secrets."db.pem".path;
    privateKeyFile = config.vaultix.secrets."db.key".path;
  };
}
