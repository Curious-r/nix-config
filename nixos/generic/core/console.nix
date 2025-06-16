{ ... }:
{
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
    earlySetup = true; # 使 console 配置生效于 initrd
    # 控制台颜色
    colors = [
      "282C34"
      "E06C75"
      "98C379"
      "E5C07B"
      "61AFEF"
      "C678DD"
      "56B6C2"
      "DCDFE4"
      "5A6374"
      "E06C75"
      "98C379"
      "E5C07B"
      "61AFEF"
      "C678DD"
      "56B6C2"
      "DCDFE4"
    ];
  };

  # https://wiki.archlinux.org/title/KMSCON
  # Use kmscon as the virtual console instead of gettys.
  # kmscon is a kms/dri-based userspace virtual terminal implementation.
  # It supports a richer feature set than the standard linux console VT,
  # including full unicode support, and when the video card supports drm should be much faster.
  services.kmscon = {
    enable = true;
    extraOptions = "--term xterm-256color";
    # Whether to use 3D hardware acceleration to render the console.
    hwRender = true;
  };
}
