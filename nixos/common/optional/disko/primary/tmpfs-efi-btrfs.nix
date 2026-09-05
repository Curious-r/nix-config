{
  sources,
  primaryDiskWwid,
  swapSize,
  ...
}:
{
  imports = [ (import "${sources.disko}/module.nix") ];
  disko = {
    devices = {
      # 定义一个磁盘
      disk.primary = {
        device = "/dev/disk/by-id/${primaryDiskWwid}";
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

            main = {
              size = "100%";
              priority = 2;
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ]; # Override existing partition
                # Subvolumes must set a mountpoint in order to be mounted,
                # unless their parent is mounted.
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
                  "@swap" = {
                    mountOptions = [ "noatime" ];
                    mountpoint = "/.swapvol";
                    swap.swapfile.size = swapSize;
                  };
                };

                mountpoint = "/.btrfs/main";
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
}
