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
        ../../home-manager/curious/generic/optional/zed-editor.nix
        ../../home-manager/curious/generic/optional/firefox.nix
        ../../home-manager/curious/Desktop-DIY-B650
      ];
    };
  };
}
