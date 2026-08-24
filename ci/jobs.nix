let
  runnerFor = {
    x86_64-linux = "ubuntu-latest";
    aarch64-linux = "ubuntu-24.04-arm";
  };

  machines = import ../machines.nix;

  mkSystemJob =
    name: machine:
    let
      system = machine.system;
    in
    {
      name = "nixos ${name} (${system})";
      target = "nixos";
      machine = name;
      system = system;
      entrypoint = "system.nix";
      attr = "${name}.config.system.build.toplevel";
      prefetch = "";
      runsOn = runnerFor.${system};
      impure = false;
    };

  mkHomeJob = machine: system: {
    name = "home-manager ${machine} (${system})";
    target = "home-manager";
    machine = machine;
    system = system;
    entrypoint = "home-manager.nix";
    attr = ''"${machine}".activationPackage'';
    prefetch = "";
    runsOn = runnerFor.${system};
    impure = false;
  };

  mkDroidJob = machine: prefetch: {
    name = "nix-on-droid ${machine} (aarch64-linux)";
    target = "nix-on-droid";
    machine = machine;
    system = "aarch64-linux";
    entrypoint = "droid.nix";
    attr = ''"${machine}".activationPackage'';
    prefetch = prefetch;
    runsOn = runnerFor.aarch64-linux;
    impure = false;
  };

  legacyJobs = [
    (mkHomeJob "curious@Laptop-Legion-R7000" "x86_64-linux")
    (mkHomeJob "curious@Router-RaspberryPi-4B-1" "aarch64-linux")
    (mkHomeJob "curious@Server-IdeaPad-G480" "x86_64-linux")
  ]
  ++
    builtins.map
      (
        machine:
        mkDroidJob machine "/nix/store/7qd99m1w65z2vgqg453nd70y60sm3kay-proot-termux-static-aarch64-unknown-linux-android-unstable-2024-05-04"
      )
      [
        "Pad-Vivo-3Pro"
        "Phone-Redmi-K50Pro"
      ];
in
builtins.sort (a: b: a.name < b.name) (
  builtins.map (name: mkSystemJob name machines.${name}) (builtins.attrNames machines) ++ legacyJobs
)
