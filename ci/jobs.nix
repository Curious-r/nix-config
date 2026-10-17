let
  runnerFor = {
    x86_64-linux = "ubuntu-latest";
    aarch64-linux = "ubuntu-24.04-arm";
  };

  nixosConfigurations = import ../nixos;
  homeConfigurations = import ../home-manager;
  nixOnDroidConfigurations = import ../nix-on-droid;

  mapAttrsToList = f: attrs: builtins.map (name: f name attrs.${name}) (builtins.attrNames attrs);

  mkNixosJob =
    configName: host:
    let
      system = host.pkgs.stdenv.hostPlatform.system;
    in
    {
      name = "nixos ${configName} (${system})";
      target = "nixos";
      configName = configName;
      system = system;
      entrypoint = "nixos/default.nix";
      attr = "${configName}.config.system.build.toplevel";
      prefetch = [ ];
      runsOn = runnerFor.${system};
    };

  mkHomeManagerJob =
    configName: home:
    let
      system = home.pkgs.stdenv.hostPlatform.system;
    in
    {
      name = "home-manager ${configName} (${system})";
      target = "home-manager";
      configName = configName;
      system = system;
      entrypoint = "home-manager/default.nix";
      attr = ''"${configName}".activationPackage'';
      prefetch = [ ];
      runsOn = runnerFor.${system};
    };

  mkNixOnDroidJob =
    configName: droid:
    let
      system = droid.pkgs.stdenv.hostPlatform.system;
    in
    {
      name = "nix-on-droid ${configName} (${system})";
      target = "nix-on-droid";
      configName = configName;
      system = system;
      entrypoint = "nix-on-droid/default.nix";
      attr = ''"${configName}".activationPackage'';
      prefetch = [
        "/nix/store/dvf2ck9bkw7yyrlkjk87xz1anaxsgrd6-proot-termux-static-aarch64-unknown-linux-android-unstable-2026-02-20"
      ];
      runsOn = runnerFor.${system};
    };

  nixosJobs = mapAttrsToList mkNixosJob nixosConfigurations;

  homeManagerJobs = mapAttrsToList mkHomeManagerJob homeConfigurations;

  nixOnDroidJobs = mapAttrsToList mkNixOnDroidJob nixOnDroidConfigurations;

  manualJobs = [ ];
in
builtins.sort (a: b: a.name < b.name) (nixosJobs ++ homeManagerJobs ++ nixOnDroidJobs ++ manualJobs)
