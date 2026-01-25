{ ... }:
{
  security.sudo-rs = {
    enable = true;
    wheelNeedsPassword = false;
  };
  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=120 # only ask for password every 2h
    # Keep SSH_AUTH_SOCK so that pam_ssh_agent_auth.so can do its magic.
    # Defaults env_keep + =SSH_AUTH_SOCK
  '';
}
