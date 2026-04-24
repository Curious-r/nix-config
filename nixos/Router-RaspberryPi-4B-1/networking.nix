{ config, lib, ... }:

let
  # -------------------------------------------------------------------------
  # [物理接口与子网定义]
  # -------------------------------------------------------------------------
  wanInterface = "enabcm6e4ei0"; # 连接光猫的物理网口
  lanInterface = "eth1"; # 我的有线内网接口 (USB 网卡)
  wlanInterface = "wlan0"; # 树莓派内置的无线网卡
  bridgeInterface = "br-lan"; # 我创建的内部局域网虚拟网桥，用于桥接有线和无线

  # 内网 IPv4 规划
  ipv4Subnet = "192.168.64.0/24";
  ipv4Gateway = "192.168.64.1";

  # 自定义内网 ULA 前缀，用于稳定的局域网 IPv6 互访
  ulaPrefix = "fd00:10:64::";
in
{
  # -------------------------------------------------------------------------
  # 1. 核心网关设置：内核 IP 转发与 RA 接收
  # -------------------------------------------------------------------------
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.${wanInterface}.accept_ra" = 2;
  };

  networking = {
    hostName = "Router-RaspberryPi-4B-1";
    timeServers = [ "ntp.aliyun.com" ];

    wireless.enable = lib.mkForce false;
    wireless.iwd.enable = lib.mkForce false;

    # -----------------------------------------------------------------------
    # 2. 桥接与物理接口基础配置
    # -----------------------------------------------------------------------
    # [测试模式修改]：暂时创建空网桥，因为还没买usb网卡，避免系统超长等待
    # bridges.${bridgeInterface}.interfaces = [ lanInterface ];
    bridges.${bridgeInterface}.interfaces = [ ];

    # [测试模式修改]：开启物理 WAN 口作为 DHCP 客户端，方便接入家用局域网排查
    # interfaces.${wanInterface}.useDHCP = false;
    interfaces.${wanInterface}.useDHCP = true;

    # interfaces.${lanInterface}.useDHCP = false;

    # 所有的内网 IP 都绑定到虚拟网桥上
    interfaces.${bridgeInterface} = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = ipv4Gateway;
          prefixLength = 24;
        }
      ];
      ipv6.addresses = [
        {
          address = "${ulaPrefix}1";
          prefixLength = 64;
        }
      ];
    };

    # -----------------------------------------------------------------------
    # 3. IPv4 NAT 伪装与内网端口映射
    # -----------------------------------------------------------------------
    nat = {
      enable = true;
      # [测试模式修改]：由于不拨号，将 NAT 出口从 ppp0 切换为物理口
      # externalInterface = "ppp0";
      externalInterface = wanInterface;

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

    # -----------------------------------------------------------------------
    # 4. 原生 Nftables 防火墙策略
    # -----------------------------------------------------------------------
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

    # -----------------------------------------------------------------------
    # 5. IPv6 公网前缀委派 (PD) 获取
    # -----------------------------------------------------------------------
    # [测试模式修改]：暂时注释掉，避免在此模式下报错
    /*
      dhcpcd = {
        enable = true;
        allowInterfaces = [ "ppp0" ];
        extraConfig = ''
          noipv6rs
          interface ppp0
          ipv6rs
          ia_pd 1 ${bridgeInterface}/0/64
        '';
      };
    */
  };

  # -------------------------------------------------------------------------
  # 6. Hostapd 无线 AP 模式设置
  # -------------------------------------------------------------------------
  services.hostapd = {
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

  # -------------------------------------------------------------------------
  # 7. PPPoE 宽带拨号
  # -------------------------------------------------------------------------
  # [测试模式修改]：暂时屏蔽拨号服务，避免无限重连
  /*
    services.pppd = {
      enable = true;
      peers.homenet = {
        autostart = true;
        enable = true;
        config = ''
          plugin pppoe.so ${wanInterface}
          file ${config.vaultix.secrets."pppoe-auth".path}
          persist
          maxfail 0
          holdoff 5
          noauth
          defaultroute
          defaultroute-metric 10
        '';
      };
    };
  */

  # -------------------------------------------------------------------------
  # 8. IPv4 DHCP 服务 (Kea)
  # -------------------------------------------------------------------------
  services.kea.dhcp4 = {
    enable = true;
    settings = {
      interfaces-config.interfaces = [ bridgeInterface ];
      lease-database = {
        name = "/var/lib/kea/dhcp4.leases";
        persist = true;
        type = "memfile";
      };
      valid-lifetime = 4000;
      subnet4 = [
        {
          id = 1;
          subnet = ipv4Subnet;
          pools = [ { pool = "192.168.64.100 - 192.168.64.200"; } ];
          option-data = [
            {
              name = "routers";
              data = ipv4Gateway;
            }
            {
              name = "domain-name-servers";
              data = "223.5.5.5, 119.29.29.29";
            }
          ];
        }
      ];
    };
  };

  # -------------------------------------------------------------------------
  # 9. IPv6 DHCPv6 服务 (Kea) - 专管内网 ULA 地址
  # -------------------------------------------------------------------------
  services.kea.dhcp6 = {
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

  # -------------------------------------------------------------------------
  # 10. IPv6 SLAAC 与 路由通告 (radvd)
  # -------------------------------------------------------------------------
  services.radvd = {
    enable = true;
    config = ''
      interface ${bridgeInterface} {
        AdvSendAdvert on;
        AdvManagedFlag on;
        AdvOtherConfigFlag on;
        RDNSS ${ulaPrefix}1 { AdvRDNSSLifetime 3600; };

        # [测试模式修改]：由于没有 ppp0，暂时注释掉公网前缀的追踪，防止报错
        # prefix ::/64 { AdvOnLink on; AdvAutonomous on; AdvRouterAddr on; };

        # 广播我的自定义 ULA 前缀
        prefix ${ulaPrefix}/64 { AdvOnLink on; AdvAutonomous on; AdvRouterAddr on; };
      };
    '';
  };
}
