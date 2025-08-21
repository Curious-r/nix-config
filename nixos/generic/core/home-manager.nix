{
  inputs,
  config,
  self,
  ...
}:
{
  imports = [ inputs.home-manager.nixosModules.home-manager ];
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    extraSpecialArgs = { inherit inputs self; };

    users.curious.imports = [
      ../../../home-manager/curious/${config.networking.hostName}
    ];
  };
}
