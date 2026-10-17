{ config, ... }:
let
  nixosRoot = ../../..;
  dirEntries = builtins.readDir nixosRoot;
  isRemoteServer =
    name: type:
    type == "directory"
    && name != "common"
    && name != config.networking.hostName
    && builtins.pathExists (nixosRoot + "/${name}/default.nix");

  remoteServers = builtins.filter (name: isRemoteServer name dirEntries.${name}) (
    builtins.attrNames dirEntries
  );
in
{
  services.fido-remote-agent = {
    enable = true;
    hosts = remoteServers;
    legacySocket = null;
    rpIdAllow = [ "pam://gen1.remote.curious.host" ];
  };
}
