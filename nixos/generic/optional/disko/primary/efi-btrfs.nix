{ primaryDiskWwid, swapSize, ... }:
{
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
              # 前面不留个1M的空白空间的话，好像nixos-anywhere部署的时候没法正确写入EFI分区
              start = "1M";
              end = "1024M";
              priority = 1;
              # 格式化成FAT32格式
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
                # unless their parent is mounted
                subvolumes = {
                  # Subvolume name is different from mountpoint
                  "@" = {
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                    mountpoint = "/";
                  };
                  # Subvolume name is the same as the mountpoint
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
    };
  };

  fileSystems = {
    "/".neededForBoot = true;
    "/nix".neededForBoot = true;
    "/boot".neededForBoot = true;
    "/persistent".neededForBoot = true;
  };
}
