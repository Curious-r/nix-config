# Host inventory shared by the traditional evaluator and the build matrix.
{
  Server-IdeaPad-G480 = {
    system = "x86_64-linux";
    specialArgs = {
      primaryDiskWwid = "ata-TOSHIBA_SLC_128GB_SN201601176";
      swapSize = "8G";
    };
  };

  Laptop-Legion-R7000 = {
    system = "x86_64-linux";
    specialArgs = {
      primaryDiskWwid = "nvme-SAMSUNG_MZVLB512HBJQ-000L2_S4DYNF0N449629";
      swapSize = "16G";
    };
  };

  Router-RaspberryPi-4B-1 = {
    system = "aarch64-linux";
    specialArgs = {
      primaryDiskWwid = "usb-SMI_USB_DISK_CCYYMMDDHHmmSSXM5IKH-0:0";
      swapSize = "1G";
    };
  };
}
