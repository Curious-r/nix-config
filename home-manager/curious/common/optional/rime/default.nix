{ ... }:
{
  home.file.".local/share/fcitx5/rime" = {
    source = ./custom;
    recursive = true;
    force = true;
  };
}
