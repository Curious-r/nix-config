{ ... }:
{
  imports = [
    ../common/core
    ../common/optional/nix/substituters/mainland.nix
    ../common/optional/nix/substituters/numtide.nix
    # ../common/optional/nix/substituters/g480.nix

    # XDG ENV
    ../common/optional/xdg-env/basic.nix
    ../common/optional/xdg-env/nvidia.nix
    ../common/optional/xdg-env/cargo.nix
    ../common/optional/xdg-env/npm.nix

    ../common/optional/bash.nix

    # Desktop
    ../common/optional/desktop/basic.nix
    ../common/optional/desktop/discrete/niri

    ../common/optional/rime
    ../common/optional/terminal/ghostty.nix
    ../common/optional/editor/zed.nix
    ../common/optional/asciinema.nix

    ../common/optional/browser/zen.nix
    ../common/optional/browser/servo.nix
    ../common/optional/mail-client/aerion.nix

    ../common/optional/openscad.nix
    ../common/optional/obs-studio.nix

    ../common/optional/rclone.nix

    ../common/optional/wechat.nix
    ../common/optional/qq.nix

    ../common/optional/mangohud.nix
  ];
  home.stateVersion = "26.11";
}
