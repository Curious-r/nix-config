{
  sources,
  ...
}:
{
  imports = [ (import "${sources.dms-plugin-registry}/nix/module.nix") ];

  programs.dms-shell = {
    enable = true;

    systemd = {
      enable = true; # Systemd service for auto-start
      restartIfChanged = true; # Auto-restart dms.service when dms-shell changes
    };

    # Core features
    enableVPN = true; # VPN management widget
    enableDynamicTheming = true; # Wallpaper-based theming (matugen)
    enableAudioWavelength = true; # Audio visualizer (cava)
    enableCalendarEvents = true; # Calendar integration (khal)

    plugins = {
      # Simply enable plugins by their ID (from the registry).
      nixMonitor.enable = true;
      nvidiaGpuMonitor.enable = true;
      powerUsagePlugin.enable = true;
      dankBatteryAlerts.enable = true;
      dockerManager.enable = true;
    };
  };

  programs.dsearch.enable = true;
}
