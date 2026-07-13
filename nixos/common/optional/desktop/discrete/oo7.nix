{ ... }:
{
  services = {
    gnome.gnome-keyring.enable = false;
    oo7.enable = true;
  };
  security.pam.services.curious.oo7.enable = true;
}
