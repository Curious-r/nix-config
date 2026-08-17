{ ... }:
{
  programs.solaar = {
    enable = true; # Enable the service
    userService = {
      enable = true;
      window = "hide"; # Show the window on startup (show, *hide*, only [window only])
      batteryIcons = "regular"; # Which battery icons to use (*regular*, symbolic, solaar)
      extraArgs = [ ]; # Extra arguments to pass to solaar on startup
    };
  };
}
