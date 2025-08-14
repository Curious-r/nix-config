{ ... }:
{
  vaultix.secrets = {
    "rclone.conf" = {
      file = ../../../../../secrets/nixos/generic/optional/curious/rclone.conf.age;
      mode = "644";
      owner = "curious";
      group = "users";
      path = "/home/curious/.config/rclone/rclone.conf";
    };
  };
  systemd.tmpfiles.settings.rclone = {
    "/home/curious/.config/rclone".d = {
      user = "curious";
      group = "users";
      mode = "0755";
    };
  };
}
