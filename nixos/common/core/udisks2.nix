{ lib, ... }:
{
  services.udisks2.enable = lib.mkDefault true;
}
