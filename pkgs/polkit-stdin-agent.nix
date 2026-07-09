{
  lib,
  rustPlatform,
  fetchFromGitea,
  nixosTests,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "polkit-stdin-agent";
  version = "0.3.2";

  src = fetchFromGitea {
    domain = "codeberg.org";
    owner = "Curiosus";
    repo = "polkit-stdin-agent";
    rev = "1215fc30c1b4979c618f7b0b0bd91db7770462cf";
    hash = "sha256-4h497EhYav7hG4x3RjlAsLla0jdnhbn0zjDd3HlgLO0=";
  };

  cargoHash = "sha256-BDPVpF+nIHCmZwUZNp6fzUL60NXWrz+eacDNTgFU+AA=";

  strictDeps = true;
  __structuredAttrs = true;

  passthru = {
    inherit (nixosTests) nixos-rebuild-target-host;
  };

  meta = {
    description = "Non-interactive polkit authentication agent that answers PAM prompts from a file descriptor";
    longDescription = ''
      Registers a per-process polkit authentication agent for a wrapped
      command and answers the PAM conversation from a file descriptor
      instead of /dev/tty, giving run0 / systemd-run the same
      "password on stdin" ergonomics as `sudo --stdin`.

      Used by `nixos-rebuild --elevate=run0 --ask-elevate-password` to
      authenticate on a target host over SSH without allocating a TTY.
    '';
    homepage = "https://codeberg.org/r-vdp/polkit-stdin-agent";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ curious ];
    platforms = lib.platforms.linux;
    mainProgram = "polkit-stdin-agent";
  };
})
