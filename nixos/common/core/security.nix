{ lib, ... }:
{
  security = {
    pam.sshAgentAuth.enable = true;
    sudo-rs = {
      enable = true;
      extraConfig = ''
        Defaults timestamp_timeout=120
      '';
    };
    polkit.enable = lib.mkDefault true;
  };
}
