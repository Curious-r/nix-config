{
  inputs,
  ...
}:
{
  imports = [ inputs.dms-plugin-registry.modules.default ];

  programs.dms-shell = {
    enable = true;

    systemd = {
      enable = true; # Systemd service for auto-start
      restartIfChanged = true; # Auto-restart dms.service when dms-shell changes
    };

    # Core features
    enableSystemMonitoring = true; # System monitoring widgets (dgop)
    enableVPN = true; # VPN management widget
    enableDynamicTheming = true; # Wallpaper-based theming (matugen)
    enableAudioWavelength = true; # Audio visualizer (cava)
    enableCalendarEvents = true; # Calendar integration (khal)
    enableClipboardPaste = true; # Pasting from the clipboard history (wtype)

    plugins = {
      # Simply enable plugins by their ID (from the registry)
      nixMonitor.enable = true;
      nvidiaGpuMonitor.enable = true;
      powerUsagePlugin.enable = true;
      dankBatteryAlerts.enable = true;
      dockerManager.enable = true;
    };
  };
}
