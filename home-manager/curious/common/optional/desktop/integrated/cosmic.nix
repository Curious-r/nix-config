{ ... }:
{
  # 临时解决使用 dbus 通道传递 xdg openURI portal 的请求无法继承到 PATH 的问题
  # 这个问题会导致 zed 或者 flakpak 应用无法正常调起浏览器
  # 参见 https://github.com/NixOS/nixpkgs/issues/189851
  systemd.user.settings.Manager.DefaultEnvironment = {
    PATH = "/run/wrappers/bin:/home/%u/.nix-profile/bin:/nix/profile/bin:/home/%u/.local/state/nix/profile/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin";
  };
}
