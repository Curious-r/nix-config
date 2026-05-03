{
  lib,
  ...
}:
{
  hardware.nvidia = {
    open = true;
    branch = "production";
    nvidiaSettings = true;

    powerManagement.enable = true;

    modesetting.enable = true;
    dynamicBoost.enable = lib.mkForce true;
  };
}
