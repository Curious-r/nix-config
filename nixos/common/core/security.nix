{ lib, ... }:
{
  security = {
    pam.sshAgentAuth.enable = true;
    polkit.enable = lib.mkDefault true;
    sudo.enable = false;
  };
}
