{
  imports = [
    ./locale.nix # localization settings
    ./nix.nix # nix settings and substituters
    ./tools.nix # basic tools
  ];

  # Back up /etc files instead of failing to activate a generation if a file already exists in /etc.
  environment.etcBackupExtension = ".bak";
}
