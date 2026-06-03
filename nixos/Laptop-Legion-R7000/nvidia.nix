{
  lib,
  ...
}:
{
  hardware.nvidia = {
    open = true;
    branch = "latest";
    nvidiaSettings = true;

    powerManagement.enable = true;

    modesetting.enable = true;
    dynamicBoost.enable = lib.mkForce true;
  };
}
