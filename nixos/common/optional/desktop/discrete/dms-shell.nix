{
  inputs,
  ...
}:
{
  imports = [
    inputs.dms.nixosModules.dank-material-shell
    inputs.dms-plugin-registry.nixosModules.default
  ];

  programs.dank-material-shell = {
    enable = true;

    systemd = {
      enable = true;
      restartIfChanged = true;
    };

    # Core features
    enableSystemMonitoring = true;
    enableVPN = true;
    enableDynamicTheming = true;
    enableAudioWavelength = true;
    enableCalendarEvents = true;

    plugins = {
      nixMonitor.enable = true;
      nvidiaGpuMonitor.enable = true;
      powerUsagePlugin.enable = true;
      dankBatteryAlerts.enable = true;
      dockerManager.enable = true;
    };
  };

  programs.dsearch.enable = true;
}
