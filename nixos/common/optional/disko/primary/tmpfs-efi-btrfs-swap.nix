{
  config,
  lib,
  sources,
  ...
}:
let
  cfg = config.disko.primary;
in
{
  imports = [ (import "${sources.disko}/module.nix") ];

  options.disko.primary = {
    diskId = lib.mkOption {
      type = lib.types.str;
      description = "The disk WWID / by-id device identifier for the primary disk.";
      example = "nvme-SAMSUNG_MZVLB512HBJQ-000L2_S4DYNF0N449629";
    };

    swapSize = lib.mkOption {
      type = lib.types.str;
      default = "8G";
      description = "Swap partition / swapfile size.";
    };
  };

  config = {
    disko = {
      devices = {
        # 定义一个磁盘
        disk.primary = {
          device = "/dev/disk/by-id/${cfg.diskId}";
          type = "disk";
          # 定义这块磁盘上的分区表
          content = {
            type = "gpt";
            # 分区列表
            partitions = {
              ESP = {
                type = "EF00";
                # 前面不留个 1M 的空白空间的话，好像 nixos-anywhere 部署的时候没法正确写入 EFI 分区。
                start = "1M";
                end = "1024M";
                priority = 1;
                # 格式化成 FAT32 格式。
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "defaults" ];
                };
              };

              # 需要落盘的文件所在的分区
              main = {
                end = "-${cfg.swapSize}";
                priority = 2;
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "@nix" = {
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                      mountpoint = "/nix";
                    };
                    "@persistent" = {
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                      mountpoint = "/persistent";
                    };
                  };

                  mountpoint = "/.btrfs/main";
                };
              };

              swap = {
                size = cfg.swapSize;
                priority = 3;
                content = {
                  type = "swap";
                };
              };
            };
          };
        };

        nodev = {
          "/" = {
            fsType = "tmpfs";
            mountOptions = [
              "defaults"
              "size=25%"
              "mode=755"
              "relatime"
            ];
          };
        };
      };
    };

    fileSystems = {
      "/".neededForBoot = true;
      "/nix".neededForBoot = true;
      "/boot".neededForBoot = true;
      "/persistent".neededForBoot = true;
    };
  };
}
