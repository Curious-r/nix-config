# Build the two Rust projects whose NixOS modules are consumed directly, while
# keeping their build dependencies inside this repository rather than their
# development flakes.
{ sources }:
let
  vaultixSource = sources.vaultix;
  pamSource = sources.pam-fido-remote;

  crateVersion =
    file:
    (builtins.fromTOML (builtins.readFile file)).package.version
      or ((builtins.fromTOML (builtins.readFile file)).workspace.package.version);
in
{
  vaultix =
    pkgs:
    pkgs.rustPlatform.buildRustPackage {
      pname = "vaultix";
      version = "${crateVersion "${vaultixSource}/Cargo.toml"}+${
        builtins.substring 0 7 vaultixSource.revision
      }";

      src = vaultixSource.outPath;
      cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
        inherit (vaultixSource) outPath;
        src = vaultixSource.outPath;
        hash = "sha256-8quSIQ80PBS210Xm13pcIEhUM2kN+d6wtRd5DDRjrK0=";
      };

      nativeBuildInputs = [ pkgs.rustPlatform.bindgenHook ];
      strictDeps = true;
      doCheck = false;

      meta = {
        mainProgram = "vaultix";
        platforms = pkgs.lib.platforms.linux;
      };
    };

  pam-fido-remote =
    pkgs:
    pkgs.rustPlatform.buildRustPackage {
      pname = "pam-fido-remote";
      version = crateVersion "${pamSource}/Cargo.toml";

      src = pamSource.outPath;
      cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
        inherit (pamSource) outPath;
        src = pamSource.outPath;
        hash = "sha256-hkW+6wRqozogLmJJf0OnqYumq1XF6DhkXKrWT+e0ktA=";
      };

      nativeBuildInputs = [
        pkgs.pkg-config
        pkgs.rustPlatform.bindgenHook
      ];
      buildInputs = [
        pkgs.pam
        pkgs.libfido2
        pkgs.openssl
      ];
      strictDeps = true;
      doCheck = false;

      postInstall = ''
        install -Dm0644 "target/${pkgs.stdenv.hostPlatform.config}/release/libpam_fido_remote.so" \
          "$out/lib/security/pam_fido_remote.so"
      '';

      meta = {
        platforms = pkgs.lib.platforms.linux;
      };
    };
}
