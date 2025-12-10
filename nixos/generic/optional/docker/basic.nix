{ lib, ... }:
{
  # Enable docker.
  virtualisation.docker = {
    enable = true;
    storageDriver = lib.mkDefault "overlay2";
  };
}
