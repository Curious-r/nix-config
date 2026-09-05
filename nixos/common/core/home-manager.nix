{
  sources,
  homeManagerModules,
  config,
  ...
}:
{
  imports = [ (import "${sources.home-manager}/nixos") ];
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    extraSpecialArgs = { inherit sources homeManagerModules; };

    users.curious.imports = [
      ../../../home-manager/curious/${config.networking.hostName}
    ];
  };
}
