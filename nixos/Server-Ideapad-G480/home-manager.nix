{ inputs, ... }:
{
  imports = [ inputs.home-manager.nixosModules.home-manager ];
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };

    users.curious = {
      imports = [
        ../../home-manager/curious/generic/core
        ../../home-manager/curious/generic/optional/nix/substituters/mainland.nix
        ../../home-manager/curious/Server-Ideapad-G480
      ];
    };
  };
}
