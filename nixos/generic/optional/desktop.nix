{ ... }:
{
  services.displayManager = {
    cosmic-greeter.enable = true;
    autoLogin = {
      enable = true;
      # Replace `yourUserName` with the actual username of user who should be automatically logged in
      user = "curious";
    };
  };
  services.desktopManager.cosmic = {
    enable = true;
    xwayland.enable = true;
  };
}
