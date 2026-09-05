{ sources, ... }:
{
  imports = [
    # Hardware configuration from the community collection.
    (import "${sources.nixos-hardware}/lenovo/legion/15arh05h")
  ];
  hardware.facter.reportPath = ./facter.json;
}
