{ ... }:
{
  vaultix = {
    settings = {
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIO/Jec53iGGzJTHHZ46iItwRJJ+I1KKgLmSfOObIUO6";
    };
    secrets = {
      "config.dae" = {
        file = ../../secrets/nixos/Server-IdeaPad-G480/config.dae.age;
        mode = "640";
        owner = "root";
        group = "users";

        insert = {
          # 替换插槽 1：局域网接口
          "801bb584bf16bb673597d2f38fd3ea6802c2438e20a8c9746df87e10df70c740" = {
            order = 0;
            content = "docker0,cs-cloudreve,cs-tts,cs-tuwunel,cs-default,cs-cinny,cs-kanidm";
          };

          # 替换插槽 2：节点分组（全地区 + 倍率分层）
          "64d82e992a388a11ee7d04a2d6efe9d540283c3815d04ac30ed9657dcb12c218" = {
            order = 1;
            content = ''
              # ==========================================
              # 0. 默认智能组（所有节点里选最快，排除过期）
              # ==========================================
              proxy {
                  filter: !name(keyword: 'Expire', '剩余', '到期', '官网', 'Traffic', 'Reset')
                  policy: min_moving_avg
              }

              # ==========================================
              # 一、地区分流组
              # ==========================================
              hk_group {
                  filter: name(keyword: 'HK', 'Hong Kong', '香港', '🇭🇰', 'HKG') && !name(keyword: 'Expire', '剩余', '到期', '官网', 'Traffic', 'Reset')
                  policy: min_moving_avg
              }
              tw_group {
                  filter: name(keyword: 'TW', 'Taiwan', '台湾', '🇹🇼', '台北', '新北', 'TPE') && !name(keyword: 'Expire', '剩余', '到期', '官网', 'Traffic', 'Reset')
                  policy: min_moving_avg
              }
              jp_group {
                  filter: name(keyword: 'JP', 'Japan', '日本', '🇯🇵', '东京', '大阪', 'TYO', 'NRT', 'KIX') && !name(keyword: 'Expire', '剩余', '到期', '官网', 'Traffic', 'Reset')
                  policy: min_moving_avg
              }
              sg_group {
                  filter: name(keyword: 'SG', 'Singapore', '新加坡', '🇸🇬', '狮城', 'SGP') && !name(keyword: 'Expire', '剩余', '到期', '官网', 'Traffic', 'Reset')
                  policy: min_moving_avg
              }
              us_group {
                  filter: name(keyword: 'US', 'America', '美国', '🇺🇸', '洛杉矶', '圣何塞', '纽约', 'LAX', 'NYC', 'SJC', 'SEA') && !name(keyword: 'Expire', '剩余', '到期', '官网', 'Traffic', 'Reset')
                  policy: min_moving_avg
              }
              kr_group {
                  filter: name(keyword: 'KR', 'Korea', '韩国', '🇰🇷', '首尔', 'Seoul') && !name(keyword: 'Expire', '剩余', '到期', '官网', 'Traffic', 'Reset')
                  policy: min_moving_avg
              }
              eu_group {
                  filter: name(keyword: 'UK', 'GB', 'Germany', 'DE', 'France', 'FR', 'Netherlands', 'NL', '欧洲', 'EU', 'London', 'Frankfurt', 'Paris', '🇬🇧', '🇩🇪') && !name(keyword: 'Expire', '剩余', '到期', '官网', 'Traffic', 'Reset')
                  policy: min_moving_avg
              }
              au_group {
                  filter: name(keyword: 'AU', 'Australia', '澳洲', '澳大利亚', 'Sydney', '悉尼', '🇦🇺') && !name(keyword: 'Expire', '剩余', '到期', '官网', 'Traffic', 'Reset')
                  policy: min_moving_avg
              }

              # ==========================================
              # 二、倍率/线路质量分层
              # ==========================================
              high_rate_group {
                  filter: name(keyword: '[2x]', '[3x]', '[5x]', 'VIP', 'Premium', 'Pro', '⚡', '倍率2', '倍率3') && !name(keyword: 'Expire', '剩余', '到期', '官网', 'Traffic', 'Reset')
                  policy: min_moving_avg
              }
              standard_rate_group {
                  filter: name(keyword: '[1x]', '标准', 'Normal', 'Basic', '倍率1') && !name(keyword: 'Expire', '剩余', '到期', '官网', 'Traffic', 'Reset', '[2x]', '[3x]', 'VIP')
                  policy: min_moving_avg
              }
              low_rate_group {
                  filter: name(keyword: '[0.1x]', '[0.2x]', '[0.3x]', '[0.4x]', '[0.5x]', '备用', 'Backup', '倍率0.1', '倍率0.2', '倍率0.3', '倍率0.4', '倍率0.5') && !name(keyword: 'Expire', '剩余', '到期', '官网', 'Traffic', 'Reset')
                  policy: min_moving_avg
              }

              # ==========================================
              # 三、协议分组
              # ==========================================
              reality_group {
                  filter: name(keyword: 'reality', 'REALITY', 'vision', 'Vision') && !name(keyword: 'Expire', '剩余', '到期', '官网', 'Traffic', 'Reset')
                  policy: min_moving_avg
              }
              trojan_group {
                  filter: name(keyword: 'trojan', 'Trojan', 'TROJAN') && !name(keyword: 'Expire', '剩余', '到期', '官网', 'Traffic', 'Reset')
                  policy: min_moving_avg
              }
            '';
          };

          # 替换插槽 3：高级分流规则
          "25857630487222bc64740fad3f2560b4fcb6fb5086fa51a933e13f217da62bcb" = {
            order = 2;
            content = ''
              # ==========================================
              # 必须直连的先写
              # ==========================================
              pname(NetworkManager, systemd-resolved, dnsmasq, aria2c) -> must_direct
              dip(224.0.0.0/3, 'ff00::/8', geoip:private, geoip:cn) -> direct
              domain(geosite:cn, geosite:microsoft, geosite:apple) -> direct
              domain(suffix:curious.host) -> direct
              domain(full:steamserver.net, geosite:steam@cn) -> direct
              domain(full:cache.nixos.org, full:curious.cachix.org) -> direct

              # ==========================================
              # 临时用一下的写这，优先级高
              # ==========================================
              # 比如说要给哪个域名换个组

              # ==========================================
              # AI 与开发者工具（很多订阅有地区限制）
              # ==========================================
              domain(geosite:openai, geosite:google, geosite:anthropic, geosite:cloudflare) -> us_group

              # ==========================================
              # 实时交互（强制走高质量/高倍率线路，确保不丢包）
              # ==========================================
              domain(geosite:discord, geosite:zoom) -> high_rate_group
              domain(suffix:microsoftteams.com, suffix:teams.cdn.office.net) -> high_rate_group

              # ==========================================
              # 流媒体视频（优先走标准倍率/地区原生解锁，节省高倍率流量）
              # ==========================================
              # 美区流媒体 -> 美国组
              domain(geosite:netflix, geosite:hbo, geosite:disney, geosite:hulu) -> us_group
              domain(suffix:paramountplus.com) -> us_group
              # 台区流媒体（如巴哈姆特）-> 台湾组
              domain(geosite:bahamut) -> tw_group
              # 日区流媒体 -> 日本组
              domain(geosite:abema, geosite:dmm, geosite:niconico) -> jp_group
              # 韩区流媒体 -> 韩国组
              domain(geosite:naver, geosite:kakao) -> kr_group
              domain(suffix:tving.com) -> kr_group
              # 欧区流媒体 -> 欧洲组（如 BBC、德国电视）
              domain(geosite:bbc) -> eu_group
              domain(suffix:zdf.de) -> eu_group
              domain(suffix:rtl.de) -> eu_group

              # ==========================================
              # 流量消耗大又没太高要求的走低费率组，未命中的也是
              # ==========================================
              domain(geosite:android, geosite:github, geosite:docker, geosite:youtube) -> low_rate_group
              fallback: low_rate_group
            '';
          };
        };
        # 自动清理未匹配的占位符（防止意外残留导致 dae 报错）。
        cleanPlaceholder = true;
      };
      "ddns-go.yaml" = {
        file = ../../secrets/nixos/Server-IdeaPad-G480/ddns-go.yaml.age;
        mode = "640";
        owner = "root";
        group = "users";
      };
    };
  };
}
