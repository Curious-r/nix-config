{
  lib,
  ...
}:
{
  hardware.nvidia = {
    open = true;
    nvidiaSettings = true;

    powerManagement.enable = true;

    modesetting.enable = true;
    dynamicBoost.enable = lib.mkForce true;
  };
}
