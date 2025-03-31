{
  inputs,
  ...
}:
{
  imports = [
    ./locale.nix # localization settings
    ./editor.nix
  ];

  # Backup etc files instead of failing to activate generation if a file already exists in /etc
  environment.etcBackupExtension = ".bak";
}
