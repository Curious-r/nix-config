{ ... }:
{
  virtualisation.docker = {
    daemon.settings.registry-mirrors = [
      "https://docker.1ms.run"
      "https://docker.mybacc.com"
      "https://dockerproxy.net"
      "https://vgsv7kpu.mirror.aliyuncs.com"
    ];
  };
}
