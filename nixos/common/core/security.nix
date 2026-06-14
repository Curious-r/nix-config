{ lib, ... }:
{
  security = {
    pam.sshAgentAuth.enable = true;
    polkit.enable = lib.mkDefault true;
  };
}
