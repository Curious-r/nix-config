{ ... }:
{
  vaultix = {
    settings = {
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIJ+tFrKE1paIOstWJyPd0WAAkwAPYFEiEWLjmuu7fnQ root@Router-RaspberryPi-4B-1";
    };
    secrets = {
      "config.dae" = {
        file = ../../secrets/nixos/Router-RaspberryPi-4B-1/config.dae.age;
        mode = "640";
        owner = "root";
        group = "users";

        insert = {
          # 替换插槽 1：局域网接口
          "56d78a9b2c1e4f3a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a" = {
            order = 0;
            content = "docker0,hs-cloudreve,hs-tts,hs-conduit,hs-default,hs-cinny,hs-kanidm";
          };

          # 替换插槽 2：高级分流规则
          "81c4b7f7e0549f1514e9cae97cf40cf133920418d3dc71bedbf60ec9bd6148cb" = {
            order = 1;
            content = ''
              # 常用开发资源走主力代理
              domain(geosite:github) -> proxy

              # AI 工具强制走美国节点
              domain(geosite:openai, geosite:anthropic) -> us_group

              # 台区专属流媒体
              domain(geosite:bahamut) -> tw_group

              # 可以在这里随时添加更多规则，无需重新加密文件！
            '';
          };
        };
        # 自动清理未匹配的占位符（防止意外残留导致 dae 报错）
        cleanPlaceholder = true;
      };
      "wifi-password".file = ../../secrets/nixos/Router-RaspberryPi-4B-1/wifi-password.age;
      "pppoe-auth".file = ../../secrets/nixos/Router-RaspberryPi-4B-1/pppoe-auth.age;
    };
  };
}
