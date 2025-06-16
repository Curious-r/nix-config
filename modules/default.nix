{
  flake = {
    flakeModules = import ./flake-parts; # My custom modules for flake-parts
    homeManagerModules = import ./home-manager; # My custom modules for Home Manager
    nixosModules = import ./nixos; # My custom modules for NixOS
  };
}
