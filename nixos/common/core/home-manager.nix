{
  sources,
  config,
  self,
  ...
}:
{
  imports = [ (import "${sources.home-manager}/nixos") ];
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    extraSpecialArgs = { inherit sources self; };

    users.curious.imports = [
      ../../../home-manager/curious/${config.networking.hostName}
    ];
  };
}
