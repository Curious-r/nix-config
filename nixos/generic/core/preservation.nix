{
  inputs,
  lib,
  ...
}:
{
  imports = [ inputs.preservation.nixosModules.preservation ];
  preservation = {
    # the module doesn't do anything unless it is enabled
    enable = lib.mkDefault true;

    preserveAt."/persistent" = {

      # preserve system directories
      directories = [
        # "/etc/secureboot"
        "/var/lib/bluetooth"
        "/var/lib/power-profiles-daemon"
        "/var/lib/systemd/coredump"
        "/var/lib/systemd/rfkill"
        "/var/lib/systemd/timers"
        "/var/lib/vaultix"
        "/var/log"
        {
          directory = "/var/lib/nixos";
          inInitrd = true;
        }
      ];

      # preserve system files
      files = [
        {
          file = "/etc/machine-id";
          how = "symlink";
          inInitrd = true;
          configureParent = true;
        }
        {
          file = "/etc/ssh/ssh_host_rsa_key";
          how = "symlink";
          configureParent = true;
        }
        {
          file = "/etc/ssh/ssh_host_rsa_key.pub";
          how = "symlink";
          configureParent = true;
        }
        {
          file = "/etc/ssh/ssh_host_ed25519_key";
          how = "symlink";
          configureParent = true;
        }
        {
          file = "/etc/ssh/ssh_host_ed25519_key.pub";
          how = "symlink";
          configureParent = true;
        }
        "/var/lib/usbguard/rules.conf"

        # creates a symlink on the volatile root
        # creates an empty directory on the persistent volume, i.e. /persistent/var/lib/systemd
        # does not create an empty file at the symlink's target (would require `createLinkTarget = true`)
        {
          file = "/var/lib/systemd/random-seed";
          how = "symlink";
          inInitrd = true;
          configureParent = true;
        }
      ];

      # preserve user-specific files, implies ownership
      users = {
        curious = {
          commonMountOptions = [
            "x-gvfs-hide"
          ];
          directories = [
            {
              directory = ".ssh";
              mode = "0700";
            }
            ".config"
            ".local/state"
            ".local/share"
          ];
          files = [
            ".gitconfig"
          ];
        };
        root = {
          # specify user home when it is not `/home/${user}`
          home = "/root";
          directories = [
            {
              directory = ".ssh";
              mode = "0700";
            }
          ];
        };
      };
    };
  };

  # Create some directories with custom permissions.
  #
  # In some configurations, the path like `/home/curious/.local` is not an immediate
  # parent of any persisted file, so it would be created with the systemd-tmpfiles
  # default ownership `root:root` and mode `0755`. This would mean that the user `curious`
  # could not create other files or directories inside `/home/curious/.local`.
  #
  # Therefore systemd-tmpfiles is used to prepare such directories with
  # appropriate permissions.
  #
  # Note that immediate parent directories of persisted files can also be
  # configured with ownership and permissions from the `parent` settings if
  # `configureParent = true` is set for the file.
  systemd.tmpfiles.settings.preservation = {
    "/home/curious/.config".d = {
      user = "curious";
      group = "users";
      mode = "0755";
    };
    "/home/curious/.local".d = {
      user = "curious";
      group = "users";
      mode = "0755";
    };
    "/home/curious/.local/share".d = {
      user = "curious";
      group = "users";
      mode = "0755";
    };
    "/home/curious/.local/state".d = {
      user = "curious";
      group = "users";
      mode = "0755";
    };
  };

  # systemd-machine-id-commit.service would fail, but it is not relevant
  # in this specific setup for a persistent machine-id so we disable it
  #
  # see the firstboot example below for an alternative approach
  systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];

  # let the service commit the transient ID to the persistent volume
  systemd.services.systemd-machine-id-commit = {
    unitConfig.ConditionPathIsMountPoint = [
      ""
      "/persistent/etc/machine-id"
    ];
    serviceConfig.ExecStart = [
      ""
      "systemd-machine-id-setup --commit --root /persistent"
    ];
  };
}
