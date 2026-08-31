let
  runnerFor = {
    x86_64-linux = "ubuntu-latest";
    aarch64-linux = "ubuntu-24.04-arm";
  };

  machines = import ../lib/machines.nix;
  homeConfigurations = import ../home-manager;
  nixOnDroidConfigurations = import ../nix-on-droid;

  # Fallback for Nix versions without builtins.mapAttrsToList (e.g. Lix 2.95)
  mapAttrsToList =
    builtins.mapAttrsToList
      or (f: attrs: builtins.map (name: f name attrs.${name}) (builtins.attrNames attrs));

  mkNixosJob = configName: host: {
    name = "nixos ${configName} (${host.system})";
    target = "nixos";
    configName = configName;
    system = host.system;
    entrypoint = "nixos/default.nix";
    attr = "${configName}.config.system.build.toplevel";
    prefetch = "";
    runsOn = runnerFor.${host.system};
    impure = false;
  };

  mkHomeManagerJob =
    configName:
    let
      # configName is "<user>@<host>" (e.g. "curious@Laptop-Legion-R7000");
      # extract host part to look up system from machines.
      hostName = builtins.elemAt (builtins.split "@" configName) 2;
      system = machines.${hostName}.system;
    in
    {
      name = "home-manager ${configName} (${system})";
      target = "home-manager";
      configName = configName;
      system = system;
      entrypoint = "home-manager/default.nix";
      attr = ''"${configName}".activationPackage'';
      prefetch = "";
      runsOn = runnerFor.${system};
      impure = false;
    };

  mkNixOnDroidJob = configName: {
    name = "nix-on-droid ${configName} (aarch64-linux)";
    target = "nix-on-droid";
    configName = configName;
    system = "aarch64-linux";
    entrypoint = "nix-on-droid/default.nix";
    attr = ''"${configName}".activationPackage'';
    prefetch = "/nix/store/dvf2ck9bkw7yyrlkjk87xz1anaxsgrd6-proot-termux-static-aarch64-unknown-linux-android-unstable-2026-02-20";
    runsOn = runnerFor.aarch64-linux;
    # Upstream embeds an absolute bootstrap store path with
    # builtins.storePath, so evaluation still requires --impure.
    impure = true;
  };

  nixosJobs = mapAttrsToList (configName: host: mkNixosJob configName host) machines;

  homeManagerJobs = mapAttrsToList (configName: _: mkHomeManagerJob configName) homeConfigurations;

  nixOnDroidJobs = mapAttrsToList (
    configName: _: mkNixOnDroidJob configName
  ) nixOnDroidConfigurations;

  manualJobs = [ ];
in
builtins.sort (a: b: a.name < b.name) (nixosJobs ++ homeManagerJobs ++ nixOnDroidJobs ++ manualJobs)
