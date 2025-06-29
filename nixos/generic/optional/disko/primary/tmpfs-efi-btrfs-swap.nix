{
  inputs,
  primaryDiskWwid,
  swapSize,
  ...
}:
{
  imports = [ inputs.disko.nixosModules.disko ];
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

            # 需要落盘的文件所在的分区
            main = {
              end = "-${swapSize}";
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
              size = swapSize;
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
}
