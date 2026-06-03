{ ... }:
{
  # https://wiki.archlinux.org/title/KMSCON
  services.kmscon = {
    enable = true;

    extraOptions = "--term xterm-256color";

    config = {
      font-name = "Monaspace Krypton";
      font-size = 16;
      hwaccel = true;
    };
  };
}
