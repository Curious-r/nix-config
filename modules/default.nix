{
  flake = {
    homeManagerModules = import ./home-manager; # My custom modules for Home Manager
    nixosModules.boot = import ./nixos/boot; # My custom modules for NixOS
  };
}
