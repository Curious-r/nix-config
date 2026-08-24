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

  # nix-on-droid stays on the existing Flake during the experiment. Its
  # entries are explicit so that the build matrix has no self-output introspection.
  mkFlakeJob =
    {
      target,
      machine,
      system,
      attr,
      prefetch ? "",
      impure ? false,
    }:
    {
      name = "${target} ${machine} (${system})";
      target = target;
      machine = machine;
      system = system;
      entrypoint = "flake";
      attr = attr;
      prefetch = prefetch;
      runsOn = runnerFor.${system};
      impure = impure;
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

  mkDroidJob =
    machine: prefetch:
    mkFlakeJob {
      target = "nix-on-droid";
      machine = machine;
      system = "aarch64-linux";
      attr = "nixOnDroidConfigurations.${machine}.config.build.activationPackage";
      prefetch = prefetch;
      impure = true;
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
