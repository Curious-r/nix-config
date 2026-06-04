{ config, lib, ... }:

let
  wanInterface = "enabcm6e4ei0"; # 当前连接到光猫的物理网口 (仅作承载层)
  lanInterface = "enu2"; # 有线内网接口
  wlanInterface = "wlan0"; # 树莓派内置无线网卡
  bridgeInterface = "br-lan"; # 局域网核心虚拟网桥

  ipv4Gateway = "192.168.32.1";
  ulaPrefix = "fd00:dafa:cade::"; # 内网固定的 IPv6 ULA 前缀
in
{
  # 基础网络设置
  networking = {
    hostName = "Router-RaspberryPi-4B-1";
    timeServers = [ "ntp.aliyun.com" ];

    # 彻底禁用旧网络管理器，由 Systemd-Networkd 全权接管
    useDHCP = false;
    useNetworkd = true;

    wireless.enable = lib.mkForce false;
    wireless.iwd.enable = lib.mkForce false;

    # NAT 与端口转发
    nat = {
      enable = true;
      # NAT 出口从物理网卡改为拨号产生的 ppp0
      externalInterface = "ppp0";
      internalInterfaces = [ bridgeInterface ];
      forwardPorts = [
        {
          sourcePort = 7931;
          destination = "192.168.1.100:7931";
          proto = "tcp";
        }
        {
          sourcePort = 7931;
          destination = "192.168.1.100:7931";
          proto = "udp";
        }
      ];
    };

    # 防火墙规则
    firewall = {
      enable = true;
      trustedInterfaces = [ bridgeInterface ];
      logReversePathDrops = true;
      logRefusedPackets = true;
      extraForwardRules = ''
        meta nfproto ipv6 tcp dport 7931 accept
        meta nfproto ipv6 udp dport 7931 accept
      '';
    };
  };

  services = {
    # PPPoE 拨号守护进程 (Systemd PPPD)
    pppd = {
      enable = true;
      peers."isp" = {
        autostart = true;
        enable = true;
        config = ''
          plugin pppoe.so ${wanInterface}
          file ${config.vaultix.secrets."pppoe-auth".path}

          persist
          maxfail 0
          defaultroute

          # 开启 IPv6 协商，为 DHCPv6-PD 获取前缀做准备
          +ipv6
          ipv6cp-use-ipaddr

          hide-password
          noauth
          nobsdcomp
          nodeflate
        '';
      };
    };

    # Systemd-Resolved: 树莓派本机 DNS 守护进程，暂时承担内网 DNS 服务端点
    resolved = {
      enable = true;
      settings = {
        Resolve = {
          # 让 resolved 额外监听局域网网桥的 IPv4 和 IPv6 的 53 端口
          DNSStubListenerExtra = [
            "${ipv4Gateway}:53"
            "[${ulaPrefix}1]:53"
          ];

          # 配置 resolved 的上游公共 DNS
          # 配置支持 DoT (DNS over TLS) 的服务器，顺便实现透明加密防污染
          DNS = [
            "223.5.5.5#dns.alicdn.com"
            "119.29.29.29#pubdns.dot.pub"
          ];

          # 开启上游 DNS 加密（国内部分运营商可能会阻断 DoT，先设为 opportunistic 测试）
          DNSOverTLS = "opportunistic";
        };
      };
    };

    # Kea DHCPv6: 内网 IPv6 状态化分配
    kea.dhcp6 = {
      enable = true;
      settings = {
        interfaces-config.interfaces = [ bridgeInterface ];
        lease-database = {
          name = "/var/lib/kea/dhcp6.leases";
          persist = true;
          type = "memfile";
        };
        valid-lifetime = 7200;
        subnet6 = [
          {
            id = 1;
            subnet = "${ulaPrefix}/64";
            pools = [ { pool = "${ulaPrefix}1000 - ${ulaPrefix}2000"; } ];
            option-data = [
              {
                name = "dns-servers";
                data = "${ulaPrefix}1";
              }
            ];
          }
        ];
      };
    };

    # Hostapd: 无线 AP 模式
    hostapd = {
      enable = true;
      radios.${wlanInterface} = {
        band = "2g";
        channel = 6;
        # 驱动要求： 必须配置国家码，才能解锁网卡发射权限
        countryCode = "CN";
        networks.${wlanInterface} = {
          ssid = "Router-RaspberryPi-4B-1";
          authentication = {
            # 使用 wpa3 会由于内置网卡闭源固件的问题导致无法连接成功，而 wpa2-sha256 会被部分 Android 设备识别为企业认证类型
            # 因此这里我们使用 wpa2-sha1 模式
            mode = "wpa2-sha1";
            wpaPasswordFile = config.vaultix.secrets."wifi-password".path;
          };
          settings.bridge = bridgeInterface;
        };
      };
    };
  };

  # Systemd-Networkd: 核心网关与链路管理
  systemd.network = {
    enable = true;

    netdevs."10-br-lan" = {
      netdevConfig = {
        Name = bridgeInterface;
        Kind = "bridge";
      };
    };

    networks = {
      # --- 物理 WAN 口：仅做 PPPoE 的承载层 ---
      "20-wan-physical" = {
        matchConfig.Name = wanInterface;
        networkConfig = {
          LinkLocalAddressing = false;
          LLDP = false;
          EmitLLDP = false;
          IPv6AcceptRA = false;
        };
        linkConfig = {
          ActivationPolicy = "up";
        };
      };

      # --- 拨号产生的逻辑接口 ppp0 ---
      "21-wan-ppp" = {
        matchConfig.Name = "ppp0";
        networkConfig = {
          IPv4Forwarding = true;
          IPv6Forwarding = true;

          DHCP = "ipv6";
          IPv6AcceptRA = true;
        };

        dhcpV6Config = {
          WithoutRA = "solicit";
          PrefixDelegationHint = "::/60";
          UseDNS = false;
        };

        # 彻底屏蔽 IPv4 和 IPv6 侧可能渗入的运营商劫持 DNS
        dhcpV4Config = {
          UseDNS = false;
        };
        ipv6AcceptRAConfig = {
          UseDNS = false;
        };
      };

      # --- 局域网物理接口绑定 ---
      "30-lan-ports" = {
        matchConfig.Name = "${lanInterface} ${wlanInterface}";
        networkConfig.Bridge = bridgeInterface;
      };

      # --- 局域网核心网桥：IP、IPv4 DHCP 与 IPv6 RA 广播 ---
      "40-br-lan" = {
        matchConfig.Name = bridgeInterface;
        address = [
          "${ipv4Gateway}/24"
          "${ulaPrefix}1/64"
        ];

        networkConfig = {
          DHCPServer = true;
          IPv6SendRA = true;
          IPv6AcceptRA = false;
          DHCPPrefixDelegation = true;
        };

        # 将 ppp0 获取到的公网前缀委派给 br-lan 分发
        dhcpPrefixDelegationConfig = {
          UplinkInterface = "ppp0";
          Announce = true;
          Assign = true;
        };

        # 内网 IPv4 DHCP 服务端设置
        dhcpServerConfig = {
          PoolOffset = 100;
          PoolSize = 100;
          DNS = [ ipv4Gateway ];
          Router = ipv4Gateway;
        };

        # 内网 IPv6 路由通告 (RA) 设置
        ipv6SendRAConfig = {
          Managed = true;
          OtherInformation = true;
          EmitDNS = true;
          DNS = "${ulaPrefix}1";
        };

        # 声明静态前缀段
        ipv6Prefixes = [ { Prefix = "${ulaPrefix}/64"; } ];
      };
    };
  };
}
