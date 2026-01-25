{ lib, ... }:
{
  # Enable the OpenSSH daemon.
  services.openssh.enable = lib.mkDefault true;
}
