{
  inputs,
  ...
}:
{
  imports = [
    ./locale.nix # localization settings
    ./tools.nix # basic tools
  ];

  # Backup etc files instead of failing to activate generation if a file already exists in /etc
  environment.etcBackupExtension = ".bak";
}
