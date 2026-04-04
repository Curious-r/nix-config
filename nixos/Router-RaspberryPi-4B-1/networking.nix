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
    # 强制接受光猫侧的 RA，确保我的 PPPoE 拨号或 DHCPv6 能获取到前缀
    "net.ipv6.conf.${wanInterface}.accept_ra" = 2;
  };

  networking = {
    hostName = "Router-RaspberryPi-4B-1";
    timeServers = [ "ntp.aliyun.com" ];

    # 虽然 common 里没开，但这里为了保险起见显式关闭无线客户端，
    # 确保我的网卡完全交给 hostapd 作为 AP 使用。
    wireless.enable = lib.mkForce false;
    wireless.iwd.enable = lib.mkForce false;

    # -----------------------------------------------------------------------
    # 2. 桥接与物理接口基础配置
    # -----------------------------------------------------------------------
    # 创建网桥，并把物理有线口直接插进网桥
    # (注意：无线口 wlan0 暂不在这里写，hostapd 启动时会自动把它桥接进来)
    # bridges.${bridgeInterface}.interfaces = [ lanInterface ];
    # 暂时创建空网桥，因为还没买usb网卡，这样可以避免系统在到达 网络目标 时的超长等待
    bridges.${bridgeInterface}.interfaces = [ ];

    # 物理接口只做二层数据包转发，不再配置任何 IP
    interfaces.${wanInterface}.useDHCP = false;
    # interfaces.${lanInterface}.useDHCP = false;

    # 所有的内网 IP 统统绑定到我的虚拟网桥上
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
      externalInterface = "ppp0"; # 拨号成功后的虚拟 WAN 接口
      internalInterfaces = [ bridgeInterface ]; # 局域网出口设为网桥

      # 把外部访问的 7931 端口转发到我内网特定机器的 7931 端口 (仅限 IPv4)
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
      trustedInterfaces = [ bridgeInterface ]; # 完全放行来自我内网网桥的所有流量

      logReversePathDrops = true;
      logRefusedPackets = true;

      # 在 FORWARD 链中放行特定 IPv6 流量
      extraForwardRules = ''
        meta nfproto ipv6 tcp dport 7931 accept
        meta nfproto ipv6 udp dport 7931 accept
      '';
    };

    # -----------------------------------------------------------------------
    # 5. IPv6 公网前缀委派 (PD) 获取
    # -----------------------------------------------------------------------
    dhcpcd = {
      enable = true;
      allowInterfaces = [ "ppp0" ];
      extraConfig = ''
        noipv6rs
        interface ppp0
        ipv6rs
        # 向上游提取一个 /64 的公网子网，并分配给我的内网网桥
        ia_pd 1 ${bridgeInterface}/0/64
      '';
    };
  };

  # -------------------------------------------------------------------------
  # 6. Hostapd 无线 AP 模式设置
  # -------------------------------------------------------------------------
  services.hostapd = {
    enable = true;
    radios.${wlanInterface} = {
      # 树莓派天线较弱，我在这里使用 2.4G 频段保证更好的穿墙与设备兼容性
      band = "2g";
      channel = 6;
      networks.${wlanInterface} = {
        ssid = "RaspberryPi-Router"; # 要广播的 Wi-Fi 名称
        authentication = {
          mode = "wpa2-sha256";
          wpaPasswordFile = config.vaultix.secrets."wifi-password".path;
        };
        # [核心逻辑]：让 hostapd 将启动后的无线网卡直接桥接到 br-lan，实现无线有线互通
        settings.bridge = bridgeInterface;
      };
    };
  };

  # -------------------------------------------------------------------------
  # 7. PPPoE 宽带拨号
  # -------------------------------------------------------------------------
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

  # -------------------------------------------------------------------------
  # 8. IPv4 DHCP 服务 (Kea)
  # -------------------------------------------------------------------------
  services.kea.dhcp4 = {
    enable = true;
    settings = {
      interfaces-config.interfaces = [ bridgeInterface ]; # 只监听我的网桥
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
            # 下发网桥自己作为 DNS 服务器 (如果我内网跑了 AdGuard/Mosdns 等)
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

        # M=1, O=1: 指示客户端使用 DHCPv6 获取 ULA 地址和 DNS
        AdvManagedFlag on;
        AdvOtherConfigFlag on;

        # 兜底 DNS 下发 (照顾不支持 DHCPv6 的 Android 设备)
        RDNSS ${ulaPrefix}1 { AdvRDNSSLifetime 3600; };

        # 动态追踪我通过 ppp0 拿到的公网前缀并广播
        prefix ::/64 { AdvOnLink on; AdvAutonomous on; AdvRouterAddr on; };

        # 广播我的自定义 ULA 前缀，确保局域网所有设备拥有稳定互通的内网 IPv6
        prefix ${ulaPrefix}/64 { AdvOnLink on; AdvAutonomous on; AdvRouterAddr on; };
      };
    '';
  };
}
