{
  pkgs,
  lib,
  config,
  ...
}:
{
  hardware.nvidia = {
    open = true; # YOU CAN SET THIS TO FALSE AND IT WILL ALSO BUILD
    nvidiaSettings = true;

    # Apply CachyOS kernel 6.19 patch to NVIDIA latest driver
    package =
      let
        base = config.boot.kernelPackages.nvidiaPackages.latest;
        cachyos-nvidia-patch = pkgs.fetchpatch {
          url = "https://raw.githubusercontent.com/CachyOS/CachyOS-PKGBUILDS/master/nvidia/nvidia-utils/kernel-6.19.patch";
          sha256 = "sha256-YuJjSUXE6jYSuZySYGnWSNG5sfVei7vvxDcHx3K+IN4=";
        };

        # Patch the appropriate driver based on config.hardware.nvidia.open
        driverAttr = if config.hardware.nvidia.open then "open" else "bin";
      in
      base
      // {
        ${driverAttr} = base.${driverAttr}.overrideAttrs (oldAttrs: {
          patches = (oldAttrs.patches or [ ]) ++ [ cachyos-nvidia-patch ];
        });
      };

    powerManagement.enable = true;

    modesetting.enable = true;
    dynamicBoost.enable = lib.mkForce true;
  };
}
