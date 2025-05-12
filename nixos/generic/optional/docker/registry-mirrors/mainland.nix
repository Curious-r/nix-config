{ ... }:
{
  virtualisation.docker = {
    daemon.settings.registry-mirrors = [
      "https://hub.rat.dev"
      "https://doublezonline.cloud"
    ];
  };
}
