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
            content = "docker*,cs-*";
          };

          # 替换插槽 2：节点分组（全地区 + 倍率分层 + 协议分层）
          "64d82e992a388a11ee7d04a2d6efe9d540283c3815d04ac30ed9657dcb12c218" = {
            order = 1;
            content = ''
              # ==========================================
              # 0. 默认智能组（排除过期节点）
              # ==========================================
              proxy {
                  filter: !name(keyword: 'Expire', '剩余', '到期', '官网', 'Traffic', 'Reset')
                  policy: min_moving_avg
              }

              # ==========================================
              # 一、地区分流组（\b 单词边界通配 + / 空格两类分隔符）
              # ==========================================
              hk_group {
                  filter: name(regex: '(?i)(🇭🇰|\bHK\b|\bHKG\b|香港|hong\s*kong)') && !name(keyword: 'Expire', '剩余', '到期')
                  policy: min_moving_avg
              }
              tw_group {
                  filter: name(regex: '(?i)(🇹🇼|\bTW\b|\bTPE\b|台湾|台北|新北)') && !name(keyword: 'Expire', '剩余', '到期')
                  policy: min_moving_avg
              }
              jp_group {
                  filter: name(regex: '(?i)(🇯🇵|\bJP\b|\bTYO\b|\bNRT\b|\bKIX\b|日本|东京|大阪)') && !name(keyword: 'Expire', '剩余', '到期')
                  policy: min_moving_avg
              }
              sg_group {
                  filter: name(regex: '(?i)(🇸🇬|\bSG\b|\bSGP\b|新加坡|狮城)') && !name(keyword: 'Expire', '剩余', '到期')
                  policy: min_moving_avg
              }
              us_group {
                  filter: name(regex: '(?i)(🇺🇸|\bUS\b|\bUSA\b|美国|洛杉矶|圣何塞|西雅图|纽约)') && !name(keyword: 'Expire', '剩余', '到期')
                  policy: min_moving_avg
              }
              ca_group {
                  filter: name(regex: '(?i)(🇨🇦|\bCA\b|加拿大|多伦多|温哥华|蒙特利尔)') && !name(keyword: 'Expire', '剩余', '到期')
                  policy: min_moving_avg
              }
              kr_group {
                  filter: name(regex: '(?i)(🇰🇷|\bKR\b|\bSEO\b|韩国|首尔)') && !name(keyword: 'Expire', '剩余', '到期')
                  policy: min_moving_avg
              }
              eu_group {
                  # 覆盖：卢森堡(LU)、英国(UK/GB)、德国(DE)、法国(FR)、荷兰(NL) 等
                  filter: name(regex: '(?i)(🇱🇺|🇬🇧|🇩🇪|🇫🇷|🇳🇱|\bLU\b|\bUK\b|\bGB\b|\bDE\b|\bFR\b|\bNL\b|\bEU\b|卢森堡|英国|德国|法国|荷兰|欧洲|伦敦|法兰克福)') && !name(keyword: 'Expire', '剩余', '到期')
                  policy: min_moving_avg
              }
              au_group {
                  filter: name(regex: '(?i)(🇦🇺|\bAU\b|\bSYD\b|澳大利亚|澳洲|悉尼)') && !name(keyword: 'Expire', '剩余', '到期')
                  policy: min_moving_avg
              }

              # ==========================================
              # 二、倍率分层组（基于 / 定界的精确匹配）
              # ==========================================
              # 低倍率：抓取 /0.1x ~ /0.9x 及备用节点
              low_rate_group {
                  filter: name(regex: '(?i)(/0\.[0-9]+x|0\.[0-9]+x|备用|backup)') && !name(keyword: 'Expire', '剩余', '到期')
                  policy: min_moving_avg
              }

              # 标准倍率：显式 /1x 或隐式纯协议标签 [A] / [H6] / [CDN]
              standard_rate_group {
                  filter: name(regex: '(?i)(\[[A-Za-z0-9]+\]|/1(\.0)?x\]?|标准|normal)') && !name(regex: '(?i)/0\.[0-9]+x') && !name(keyword: 'Expire', '剩余', '到期')
                  policy: min_moving_avg
              }

              # 高倍率：2x 及以上
              high_rate_group {
                  filter: name(regex: '(?i)(/[2-9](\.[0-9]+)?x|倍率[2-9]|vip|premium|⚡)') && !name(regex: '(?i)/0\.[0-9]+x') && !name(keyword: 'Expire', '剩余', '到期')
                  policy: min_moving_avg
              }

              # ==========================================
              # 三、协议分组（前缀边界匹配）
              # ==========================================
              hysteria_group {
                  filter: name(regex: '(?i)\[H6?(/|\])') && !name(keyword: 'Expire', '剩余', '到期')
                  policy: min_moving_avg
              }
              anytls_group {
                  filter: name(regex: '(?i)\[A(/|\])') && !name(keyword: 'Expire', '剩余', '到期')
                  policy: min_moving_avg
              }
              cdn_group {
                  filter: name(regex: '(?i)\[CDN(/|\])') && !name(keyword: 'Expire', '剩余', '到期')
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
