{ pkgs, ... }:

let
  # -------------------------------------------------------------------------
  # [接口与子网定义]
  # 部署前务必通过 `ip link` 确认网卡的实际名称。
  # -------------------------------------------------------------------------
  wanInterface = "eth0"; # 连接光猫的物理接口
  lanInterface = "eth1"; # 连接内网交换机/设备的物理接口 (如 USB 网卡)

  ipv4Subnet = "192.168.1.0/24";
  ipv4Gateway = "192.168.1.1";

  # 自定义内网 ULA 前缀，用于稳定的局域网 IPv6 互访
  ulaPrefix = "fd00:10:40::";
in
{
  environment.systemPackages = [
    pkgs.impala
  ];

  # -------------------------------------------------------------------------
  # 1. 核心网关设置：内核 IP 转发与 RA 接收
  # -------------------------------------------------------------------------
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    # 强制接受光猫侧的 RA，确保 PPPoE 或 DHCPv6 能获取到前缀
    "net.ipv6.conf.${wanInterface}.accept_ra" = 2;
  };

  networking = {
    hostName = "Router-RaspberryPi-4B-1";
    timeServers = [ "ntp.aliyun.com" ];
    wireless.iwd.enable = true;

    # -----------------------------------------------------------------------
    # 2. 物理接口基础配置
    # -----------------------------------------------------------------------
    interfaces.${wanInterface}.useDHCP = false;

    interfaces.${lanInterface} = {
      useDHCP = false;
      # 绑定 IPv4 和 IPv6(ULA) 网关地址
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
      internalInterfaces = [ lanInterface ];

      # 将外部访问的 7931 端口转发到特定的内网机器 (仅限 IPv4)
      forwardPorts = [
        {
          sourcePort = 7931;
          destination = "192.168.1.100:7931"; # 替换为内网目标机器的真实 IPv4
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
      trustedInterfaces = [ lanInterface ]; # 完全放行来自内网的流量

      logReversePathDrops = true;
      logRefusedPackets = true;

      # 使用原生 nftables 语法，在 FORWARD 链中放行特定流量
      extraForwardRules = ''
                # 放行外部 IPv6 访问内网机器的 7931 端口
                # (如果想限制目标机器，可以加上 `ip6 daddr <目标IPv6地址>`)
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
                # 提取 /64 公网子网分配给 LAN 接口
                ia_pd 1 ${lanInterface}/0/64
              '';
    };
  };

  # -------------------------------------------------------------------------
  # 6. PPPoE 宽带拨号
  # -------------------------------------------------------------------------
  services.pppd = {
    enable = true;
    peers = {
      homenet = {
        autostart = true;
        enable = true;
        config = ''
                    plugin pppoe.so ${wanInterface}
                    name "YOUR_PPPOE_USERNAME" # <--- 替换为你的宽带账号
                    password "YOUR_PPPOE_PASSWORD" # <--- 替换为你的宽带密码
                    persist
                    maxfail 0
                    holdoff 5
                    noauth
                    defaultroute
                    defaultroute-metric 10
                  '';
      };
    };
  };

  # -------------------------------------------------------------------------
  # 7. IPv4 DHCP 服务 (Kea)
  # -------------------------------------------------------------------------
  services.kea.dhcp4 = {
    enable = true;
    settings = {
      interfaces-config.interfaces = [ lanInterface ];
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
          pools = [ { pool = "192.168.1.100 - 192.168.1.200"; } ];
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
  # 8. IPv6 DHCPv6 服务 (Kea) - 专管内网 ULA 地址
  # -------------------------------------------------------------------------
  services.kea.dhcp6 = {
    enable = true;
    settings = {
      interfaces-config.interfaces = [ lanInterface ];
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
            # 下发网关自己作为 DNS 服务器 (如果内网跑了 AdGuard/Mosdns 等)
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
  # 9. IPv6 SLAAC 与 路由通告 (radvd) - 混合模式
  # -------------------------------------------------------------------------
  services.radvd = {
    enable = true;
    config = ''
            interface ${lanInterface} {
              AdvSendAdvert on;
              
              # M=1, O=1: 指示客户端使用 DHCPv6 获取 ULA 地址和 DNS
              AdvManagedFlag on; 
              AdvOtherConfigFlag on; 

              # 兜底 DNS 下发 (照顾不支持 DHCPv6 的 Android 设备)
              RDNSS ${ulaPrefix}1 {
                AdvRDNSSLifetime 3600;
              };

              # A=1: 动态追踪光猫分配的公网前缀
              prefix ::/64 {
                AdvOnLink on;
                AdvAutonomous on;
                AdvRouterAddr on;
              };

              # A=1: 广播 ULA 前缀 (确保全设备能生成内网 IPv6)
              prefix ${ulaPrefix}/64 {
                AdvOnLink on;
                AdvAutonomous on;
                AdvRouterAddr on;
              };
            };
          '';
  };
}
