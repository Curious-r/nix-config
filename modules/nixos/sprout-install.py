#! @python3@/bin/python3 -B

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence


EFI_SYS_MOUNT_POINT = Path("@efiSysMountPoint@")
SPROUT_BINARY_SOURCE = Path("@sproutBinary@")

NIX = "@nix@/bin/nix-env"
EFIBOOTMGR = "@efibootmgr@/bin/efibootmgr"
FINDMNT = "@util-linux@/bin/findmnt"
LSBLK = "@util-linux@/bin/lsblk"

TIMEOUT = int("@timeout@")
CONFIGURATION_LIMIT = int("@configurationLimit@")

CAN_TOUCH_EFI_VARIABLES = "@canTouchEfiVariables@" == "1"
EFI_INSTALL_AS_REMOVABLE = "@efiInstallAsRemovable@" == "1"

FIRMWARE_ENTRY_LABEL = @firmwareEntryLabel@

DRIVERS: dict[str, str] = json.loads(r'''@drivers@''')


SPROUT_DIR = Path("EFI/Sprout")
NIXOS_DIR = SPROUT_DIR / "nixos"
DRIVERS_DIR = SPROUT_DIR / "drivers"
SPROUT_BINARY = SPROUT_DIR / "sprout.efi"
SPROUT_CONFIG = Path("sprout.toml")

FIRMWARE_LOADER_PATH = r"\EFI\Sprout\sprout.efi"

_MACHINE_BOOT_FALLBACKS = {
    "x86_64": "BOOTX64.EFI",
    "amd64": "BOOTX64.EFI",
    "aarch64": "BOOTAA64.EFI",
    "arm64": "BOOTAA64.EFI",
}


libc = ctypes.CDLL(None, use_errno=True)


@dataclass(frozen=True)
class SystemIdentifier:
    profile: str | None
    generation: int


@dataclass(frozen=True)
class BootSpec:
    init: Path
    toplevel: Path
    label: str
    kernel: Path | None
    initrd: Path | None
    initrd_secrets: Path | None
    extra_initrds: tuple[Path, ...]
    kernel_params: tuple[str, ...]
    specialisations: dict[str, "BootSpec"]


@dataclass(frozen=True)
class BootArtifact:
    destination: Path
    source: Path
    initrd_secrets: Path | None
    generation: int
    critical: bool


@dataclass(frozen=True)
class BootEntry:
    identifier: str
    title: str
    sort_key: str
    kernel: Path
    initrds: tuple[Path, ...]
    options: tuple[str, ...]
    artifacts: tuple[BootArtifact, ...]
    critical: bool


def run(
    command: Sequence[str | Path],
    *,
    stdout: Any = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(part) for part in command],
        check=True,
        text=True,
        stdout=stdout,
        stderr=sys.stderr,
    )


def capture(command: Sequence[str | Path]) -> str:
    return run(command, stdout=subprocess.PIPE).stdout.strip()


def quote_toml(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def array_toml(values: Sequence[str]) -> str:
    return "[" + ", ".join(quote_toml(value) for value in values) + "]"


def uefi_path(relative: Path) -> str:
    return "\\" + "\\".join(relative.parts)


def fsync_path(path: Path) -> None:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    except OSError:
        return

    try:
        os.fsync(fd)
    except OSError:
        pass
    finally:
        os.close(fd)


def sync_filesystem(path: Path) -> None:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    except OSError as exc:
        print(f"warning: could not open {path} for sync: {exc}", file=sys.stderr)
        return

    try:
        result = libc.syncfs(fd)
        if result != 0:
            error = ctypes.get_errno()
            print(
                f"warning: could not sync {path}: {os.strerror(error)}",
                file=sys.stderr,
            )
    finally:
        os.close(fd)


def atomic_copy(
    source: Path,
    destination: Path,
    *,
    replace: bool,
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)

    if not replace and destination.exists():
        return

    temporary_path: Path | None = None

    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            dir=destination.parent,
            prefix=f".{destination.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)

        with source.open("rb") as source_file, temporary_path.open("wb") as target:
            shutil.copyfileobj(source_file, target)
            target.flush()
            os.fsync(target.fileno())

        os.replace(temporary_path, destination)
        fsync_path(destination.parent)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def atomic_write_text(
    destination: Path,
    contents: str,
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)

    temporary_path: Path | None = None

    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=destination.parent,
            prefix=f".{destination.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)
            temporary.write(contents)
            temporary.flush()
            os.fsync(temporary.fileno())

        os.replace(temporary_path, destination)
        fsync_path(destination.parent)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def generation_directory(
    profile: str | None,
    generation: int,
) -> Path:
    if profile is None:
        return Path(f"/nix/var/nix/profiles/system-{generation}-link")

    return Path(
        f"/nix/var/nix/profiles/system-profiles/{profile}-{generation}-link"
    )


def system_directory(
    profile: str | None,
    generation: int,
    specialisation: str | None,
) -> Path:
    directory = generation_directory(profile, generation)

    if specialisation is None:
        return directory

    return directory / "specialisation" / specialisation


def get_generations(
    profile: str | None = None,
) -> list[SystemIdentifier]:
    profile_path = Path("/nix/var/nix/profiles/system")

    if profile is not None:
        profile_path = Path(
            f"/nix/var/nix/profiles/system-profiles/{profile}"
        )

    output = capture(
        [
            NIX,
            "--list-generations",
            "-p",
            profile_path,
        ]
    )

    generations: list[SystemIdentifier] = []

    for line in output.splitlines():
        fields = line.split()
        if not fields:
            continue

        try:
            generation = int(fields[0])
        except ValueError:
            continue

        generations.append(
            SystemIdentifier(
                profile=profile,
                generation=generation,
            )
        )

    if CONFIGURATION_LIMIT == 0:
        return generations

    return generations[-CONFIGURATION_LIMIT:]


def get_profiles() -> list[str]:
    directory = Path("/nix/var/nix/profiles/system-profiles")

    if not directory.is_dir():
        return []

    profiles: list[str] = []

    for entry in directory.iterdir():
        if entry.name.endswith("-link"):
            continue

        if entry.is_symlink():
            profiles.append(entry.name)

    return sorted(profiles)


def load_bootspec(
    profile: str | None,
    generation: int,
) -> BootSpec | None:
    system_path = system_directory(profile, generation, None)
    bootspec_path = (system_path / "boot.json").resolve()

    if not bootspec_path.is_file():
        print(
            "warning: skipping generation "
            f"{generation}"
            + (f" of profile {profile}" if profile else "")
            + f": {bootspec_path} does not exist",
            file=sys.stderr,
        )
        return None

    try:
        with bootspec_path.open("r", encoding="utf-8") as file:
            document = json.load(file)
    except ValueError as exc:
        print(
            f"error: malformed JSON in {bootspec_path}: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1) from exc

    return bootspec_from_json(document)


def bootspec_from_json(
    document: dict[str, Any],
) -> BootSpec:
    main = document.get("org.nixos.bootspec.v1")

    if not isinstance(main, dict):
        raise RuntimeError(
            'boot.json does not contain "org.nixos.bootspec.v1"'
        )

    if "init" not in main:
        raise RuntimeError(
            'boot.json does not contain "org.nixos.bootspec.v1.init"'
        )

    if "toplevel" not in main:
        raise RuntimeError(
            'boot.json does not contain "org.nixos.bootspec.v1.toplevel"'
        )

    kernel_value = main.get("kernel")
    initrd_value = main.get("initrd")
    initrd_secrets_value = main.get("initrdSecrets")

    kernel = Path(str(kernel_value)) if kernel_value is not None else None
    initrd = Path(str(initrd_value)) if initrd_value is not None else None
    initrd_secrets = (
        Path(str(initrd_secrets_value))
        if initrd_secrets_value is not None
        else None
    )

    extra_initrd_extension = document.get(
        "org.nixos.extra-initrd.v1",
        {},
    )

    if not isinstance(extra_initrd_extension, dict):
        raise RuntimeError(
            'boot.json contains an invalid "org.nixos.extra-initrd.v1" extension'
        )

    extra_initrd_values = extra_initrd_extension.get("paths", [])

    if not isinstance(extra_initrd_values, list):
        raise RuntimeError(
            'boot.json "org.nixos.extra-initrd.v1.paths" is not an array'
        )

    specialisation_document = document.get(
        "org.nixos.specialisation.v1",
        {},
    )

    if not isinstance(specialisation_document, dict):
        raise RuntimeError(
            'boot.json contains an invalid "org.nixos.specialisation.v1" extension'
        )

    specialisations = {
        name: bootspec_from_json(value)
        for name, value in specialisation_document.items()
    }

    kernel_params_value = main.get("kernelParams", [])

    if not isinstance(kernel_params_value, list):
        raise RuntimeError(
            'boot.json "kernelParams" is not an array'
        )

    return BootSpec(
        init=Path(str(main["init"])),
        toplevel=Path(str(main["toplevel"])),
        label=str(main.get("label", "")),
        kernel=kernel,
        initrd=initrd,
        initrd_secrets=initrd_secrets,
        extra_initrds=tuple(
            Path(str(path))
            for path in extra_initrd_values
        ),
        kernel_params=tuple(
            str(parameter)
            for parameter in kernel_params_value
        ),
        specialisations=specialisations,
    )


def artifact_path(
    kind: str,
    source: Path,
    extra: str = "",
) -> Path:
    identity = "\n".join(
        [
            kind,
            str(source.resolve()),
            extra,
        ]
    )

    digest = hashlib.sha256(
        identity.encode("utf-8")
    ).hexdigest()

    suffix = {
        "kernel": ".efi",
        "initrd": ".img",
        "extra-initrd": ".img",
    }[kind]

    return NIXOS_DIR / f"{kind}-{digest}{suffix}"


def specialisation_suffix(name: str) -> str:
    digest = hashlib.sha256(
        name.encode("utf-8")
    ).hexdigest()

    return digest[:12]


def entry_identifier(
    profile: str | None,
    generation: int,
    specialisation: str | None,
) -> str:
    if profile is None:
        identifier = f"nixos-g{generation}"
    else:
        profile_id = re.sub(
            r"[^A-Za-z0-9._-]+",
            "-",
            profile,
        ).strip("-")

        identifier = f"nixos-p-{profile_id}-g{generation}"

    if specialisation is not None:
        identifier += f"-s-{specialisation_suffix(specialisation)}"

    return identifier


def entry_title(
    profile: str | None,
    generation: int,
    specialisation: str | None,
    bootspec: BootSpec,
) -> str:
    title = f"NixOS Generation {generation}"

    if profile is not None:
        title = f"NixOS {profile} Generation {generation}"

    if specialisation is not None:
        title += f" ({specialisation})"

    if bootspec.label:
        title += f": {bootspec.label}"

    return title


def prepare_entry(
    profile: str | None,
    generation: int,
    specialisation: str | None,
    bootspec: BootSpec,
    *,
    current_toplevel: Path,
) -> BootEntry | None:
    if specialisation is None:
        selected_bootspec = bootspec
    else:
        selected_bootspec = bootspec.specialisations[specialisation]

    critical = selected_bootspec.toplevel.resolve() == current_toplevel

    if selected_bootspec.kernel is None:
        message = (
            f"generation {generation}"
            + (
                f" of profile {profile}"
                if profile is not None
                else ""
            )
            + (
                f" specialisation {specialisation}"
                if specialisation is not None
                else ""
            )
            + " has no kernel in its BootSpec"
        )

        if critical:
            raise RuntimeError(message)

        print(f"warning: {message}; skipping", file=sys.stderr)
        return None

    required_sources = [selected_bootspec.kernel]

    if selected_bootspec.initrd is not None:
        required_sources.append(selected_bootspec.initrd)

    required_sources.extend(selected_bootspec.extra_initrds)

    if selected_bootspec.initrd_secrets is not None:
        required_sources.append(selected_bootspec.initrd_secrets)

    missing_sources = [
        source
        for source in required_sources
        if not source.exists()
    ]

    if missing_sources:
        message = (
            f"generation {generation}"
            + (
                f" of profile {profile}"
                if profile is not None
                else ""
            )
            + (
                f" specialisation {specialisation}"
                if specialisation is not None
                else ""
            )
            + " references missing boot files: "
            + ", ".join(str(source) for source in missing_sources)
        )

        if critical:
            raise RuntimeError(message)

        print(f"warning: {message}; skipping", file=sys.stderr)
        return None

    kernel_destination = artifact_path(
        "kernel",
        selected_bootspec.kernel,
    )

    artifacts = [
        BootArtifact(
            destination=kernel_destination,
            source=selected_bootspec.kernel,
            initrd_secrets=None,
            generation=generation,
            critical=critical,
        )
    ]

    initrd_destinations: list[Path] = []

    if selected_bootspec.initrd is not None:
        initrd_destination = artifact_path(
            "initrd",
            selected_bootspec.initrd,
            (
                str(selected_bootspec.initrd_secrets)
                if selected_bootspec.initrd_secrets is not None
                else ""
            ),
        )

        initrd_destinations.append(initrd_destination)

        artifacts.append(
            BootArtifact(
                destination=initrd_destination,
                source=selected_bootspec.initrd,
                initrd_secrets=selected_bootspec.initrd_secrets,
                generation=generation,
                critical=critical,
            )
        )

    extra_initrd_destinations: list[Path] = []

    for extra_initrd in selected_bootspec.extra_initrds:
        destination = artifact_path(
            "extra-initrd",
            extra_initrd,
        )

        extra_initrd_destinations.append(destination)

        artifacts.append(
            BootArtifact(
                destination=destination,
                source=extra_initrd,
                initrd_secrets=None,
                generation=generation,
                critical=critical,
            )
        )

    initrds = tuple(
        initrd_destinations + extra_initrd_destinations
    )

    identifier = entry_identifier(
        profile,
        generation,
        specialisation,
    )

    sort_key = f"{generation:020d}"

    options = (
        f"init={selected_bootspec.init}",
        *selected_bootspec.kernel_params,
    )

    return BootEntry(
        identifier=identifier,
        title=entry_title(
            profile,
            generation,
            specialisation,
            selected_bootspec,
        ),
        sort_key=sort_key,
        kernel=kernel_destination,
        initrds=initrds,
        options=tuple(options),
        artifacts=tuple(artifacts),
        critical=critical,
    )


def collect_entries(
    *,
    current_toplevel: Path,
) -> list[BootEntry]:
    generations = get_generations()

    for profile in get_profiles():
        generations.extend(
            get_generations(profile)
        )

    if not generations:
        raise RuntimeError(
            "no NixOS generations found in /nix/var/nix/profiles; "
            "refusing to remove all Sprout boot files"
        )

    entries: list[BootEntry] = []

    for identifier in generations:
        bootspec = load_bootspec(
            identifier.profile,
            identifier.generation,
        )

        if bootspec is None:
            continue

        main_entry = prepare_entry(
            identifier.profile,
            identifier.generation,
            None,
            bootspec,
            current_toplevel=current_toplevel,
        )

        if main_entry is not None:
            entries.append(main_entry)

        for specialisation in sorted(
            bootspec.specialisations
        ):
            specialisation_entry = prepare_entry(
                identifier.profile,
                identifier.generation,
                specialisation,
                bootspec,
                current_toplevel=current_toplevel,
            )

            if specialisation_entry is not None:
                entries.append(specialisation_entry)

    if not entries:
        raise RuntimeError(
            "no valid NixOS BootSpec entries found; "
            "refusing to remove all Sprout boot files"
        )

    if not any(entry.critical for entry in entries):
        raise RuntimeError(
            "the requested NixOS toplevel is not present in the "
            "selected generations; refusing to install a boot menu "
            "that cannot boot the target system"
        )

    return entries


def write_initrd_with_secrets(
    artifact: BootArtifact,
) -> None:
    assert artifact.initrd_secrets is not None

    artifact.destination.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    temporary_path: Path | None = None

    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            dir=artifact.destination.parent,
            prefix=f".{artifact.destination.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)

        with artifact.source.open("rb") as source_file, temporary_path.open(
            "wb"
        ) as target:
            shutil.copyfileobj(source_file, target)
            target.flush()
            os.fsync(target.fileno())

        try:
            run(
                [
                    artifact.initrd_secrets,
                    temporary_path,
                ]
            )
        except subprocess.CalledProcessError:
            if artifact.critical:
                raise RuntimeError(
                    "failed to append initrd secrets to "
                    f"{artifact.source}"
                ) from None

            if not artifact.destination.exists():
                atomic_copy(
                    artifact.source,
                    artifact.destination,
                    replace=False,
                )

            print(
                "warning: failed to update initrd secrets for older "
                f"generation {artifact.generation}; keeping the previous "
                "initrd if available",
                file=sys.stderr,
            )
            return

        with temporary_path.open("rb") as result:
            os.fsync(result.fileno())

        os.replace(
            temporary_path,
            artifact.destination,
        )
        fsync_path(artifact.destination.parent)

        temporary_path = None
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def write_artifact(
    artifact: BootArtifact,
) -> None:
    if artifact.initrd_secrets is not None:
        if (
            artifact.destination.exists()
            and not artifact.critical
        ):
            # Older generations can retain an existing valid initrd when
            # secret material is no longer available.
            return

        write_initrd_with_secrets(artifact)
        return

    atomic_copy(
        artifact.source,
        artifact.destination,
        replace=False,
    )


def write_boot_files(
    entries: Sequence[BootEntry],
) -> set[Path]:
    artifacts: dict[Path, BootArtifact] = {}

    for entry in entries:
        for artifact in entry.artifacts:
            existing = artifacts.get(artifact.destination)

            if existing is None or (
                artifact.critical and not existing.critical
            ):
                artifacts[artifact.destination] = artifact

    for artifact in artifacts.values():
        write_artifact(artifact)

    return set(artifacts)


def install_drivers() -> dict[str, Path]:
    installed: dict[str, Path] = {}

    for name, source_string in sorted(DRIVERS.items()):
        if not re.fullmatch(
            r"[A-Za-z0-9._-]+",
            name,
        ):
            raise RuntimeError(
                f"invalid Sprout driver name: {name!r}"
            )

        source = Path(source_string)

        if not source.is_file():
            raise RuntimeError(
                f"Sprout driver {name!r} does not exist: {source}"
            )

        destination = DRIVERS_DIR / f"{name}.efi"

        atomic_copy(
            source,
            destination,
            replace=False,
        )

        installed[name] = destination

    return installed


def generate_sprout_config(
    entries: Sequence[BootEntry],
    default_entry: str,
    drivers: dict[str, Path],
) -> str:
    lines: list[str] = [
        "version = 1",
        "",
        "[options]",
        f"default-entry = {quote_toml(default_entry)}",
        f"menu-timeout = {TIMEOUT}",
    ]

    for name, path in sorted(drivers.items()):
        lines.extend(
            [
                "",
                f"[drivers.{quote_toml(name)}]",
                f"path = {quote_toml(uefi_path(path))}",
            ]
        )

    for entry in entries:
        lines.extend(
            [
                "",
                f"[entries.{quote_toml(entry.identifier)}]",
                f"title = {quote_toml(entry.title)}",
                f"actions = {array_toml([entry.identifier])}",
                f"sort-key = {quote_toml(entry.sort_key)}",
            ]
        )

    for entry in entries:
        lines.extend(
            [
                "",
                f"[actions.{quote_toml(entry.identifier)}]",
                (
                    "chainload.path = "
                    + quote_toml(uefi_path(entry.kernel))
                ),
                (
                    "chainload.options = "
                    + array_toml(entry.options)
                ),
            ]
        )

        if len(entry.initrds) == 1:
            lines.append(
                "chainload.linux-initrd = "
                + quote_toml(uefi_path(entry.initrds[0]))
            )
        elif len(entry.initrds) > 1:
            lines.append(
                "chainload.linux-initrd-chain = "
                + array_toml(
                    [uefi_path(path) for path in entry.initrds]
                )
            )

    lines.append("")

    return "\n".join(lines)


def install_sprout_binary() -> None:
    destination = EFI_SYS_MOUNT_POINT / SPROUT_BINARY

    if not SPROUT_BINARY_SOURCE.is_file():
        raise RuntimeError(
            f"Sprout EFI binary does not exist: {SPROUT_BINARY_SOURCE}"
        )

    atomic_copy(
        SPROUT_BINARY_SOURCE,
        destination,
        replace=True,
    )


def removable_loader_name() -> str:
    machine = os.uname().machine.lower()

    try:
        return _MACHINE_BOOT_FALLBACKS[machine]
    except KeyError as exc:
        raise RuntimeError(
            f"unsupported architecture for removable EFI fallback: {machine}"
        ) from exc


def install_removable_loader() -> None:
    destination = (
        EFI_SYS_MOUNT_POINT
        / "EFI"
        / "BOOT"
        / removable_loader_name()
    )

    source = EFI_SYS_MOUNT_POINT / SPROUT_BINARY

    atomic_copy(
        source,
        destination,
        replace=True,
    )


def check_mountpoint() -> None:
    try:
        source = capture(
            [
                FINDMNT,
                "--noheadings",
                "--output",
                "SOURCE",
                "--target",
                EFI_SYS_MOUNT_POINT,
            ]
        )
    except subprocess.CalledProcessError:
        raise RuntimeError(
            f"{EFI_SYS_MOUNT_POINT} is not a mounted filesystem"
        ) from None

    if not source:
        raise RuntimeError(
            f"{EFI_SYS_MOUNT_POINT} is not a mounted filesystem"
        )

    filesystem_type = capture(
        [
            FINDMNT,
            "--noheadings",
            "--output",
            "FSTYPE",
            "--target",
            EFI_SYS_MOUNT_POINT,
        ]
    )

    if filesystem_type.lower() != "vfat":
        raise RuntimeError(
            f"{EFI_SYS_MOUNT_POINT} is mounted as {filesystem_type!r}; "
            "Sprout currently requires a vfat ESP"
        )


def check_efivars() -> None:
    efivars = Path("/sys/firmware/efi/efivars")

    if not efivars.is_dir():
        raise RuntimeError(
            "EFI variables are unavailable at /sys/firmware/efi/efivars"
        )

    try:
        filesystem_type = capture(
            [
                FINDMNT,
                "--noheadings",
                "--output",
                "FSTYPE",
                "--target",
                efivars,
            ]
        )
    except subprocess.CalledProcessError:
        raise RuntimeError(
            "efivarfs is not mounted at /sys/firmware/efi/efivars"
        ) from None

    if filesystem_type != "efivarfs":
        raise RuntimeError(
            "EFI variables are not backed by efivarfs"
        )


def get_esp_device() -> tuple[str, str]:
    source = capture(
        [
            FINDMNT,
            "--noheadings",
            "--output",
            "SOURCE",
            "--target",
            EFI_SYS_MOUNT_POINT,
        ]
    )

    parent = capture(
        [
            LSBLK,
            "--noheadings",
            "--output",
            "PKNAME",
            source,
        ]
    )

    partition = capture(
        [
            LSBLK,
            "--noheadings",
            "--output",
            "PARTN",
            source,
        ]
    )

    if not parent:
        raise RuntimeError(
            f"could not determine the parent disk of ESP device {source}"
        )

    if not partition or not partition.isdigit():
        raise RuntimeError(
            f"could not determine the partition number of ESP device {source}"
        )

    return f"/dev/{parent}", partition


def install_nvram_entry() -> None:
    check_efivars()

    existing = capture(
        [
            EFIBOOTMGR,
            "-v",
        ]
    )

    normalized_loader = FIRMWARE_LOADER_PATH.lower()

    label_seen = False
    matching_loader = False

    for line in existing.splitlines():
        if not re.match(
            r"^Boot[0-9A-Fa-f]{4}\*?\s",
            line,
        ):
            continue

        normalized_line = line.lower()

        if FIRMWARE_ENTRY_LABEL.lower() in normalized_line:
            label_seen = True

            if normalized_loader in normalized_line:
                matching_loader = True

    if matching_loader:
        return

    if label_seen:
        raise RuntimeError(
            f"an existing UEFI entry named {FIRMWARE_ENTRY_LABEL!r} "
            f"does not point to {FIRMWARE_LOADER_PATH}"
        )

    disk, partition = get_esp_device()

    run(
        [
            EFIBOOTMGR,
            "-c",
            "-d",
            disk,
            "-p",
            partition,
            "-L",
            FIRMWARE_ENTRY_LABEL,
            "-l",
            FIRMWARE_LOADER_PATH,
        ]
    )


def garbage_collect(
    entries: Sequence[BootEntry],
    drivers: dict[str, Path],
) -> None:
    keep = {
        EFI_SYS_MOUNT_POINT / artifact.destination
        for entry in entries
        for artifact in entry.artifacts
    }

    keep.update(
        EFI_SYS_MOUNT_POINT / path
        for path in drivers.values()
    )

    for directory in (
        EFI_SYS_MOUNT_POINT / NIXOS_DIR,
        EFI_SYS_MOUNT_POINT / DRIVERS_DIR,
    ):
        if not directory.exists():
            continue

        for path in sorted(
            directory.rglob("*"),
            key=lambda value: len(value.parts),
            reverse=True,
        ):
            if path.is_file() or path.is_symlink():
                if path not in keep:
                    path.unlink(missing_ok=True)

            elif path.is_dir():
                try:
                    path.rmdir()
                except OSError:
                    pass


def find_default_entry(
    entries: Sequence[BootEntry],
) -> BootEntry:
    for entry in entries:
        if entry.critical:
            return entry

    raise RuntimeError(
        "could not determine the current NixOS boot entry"
    )


def install_bootloader(
    default_toplevel: Path,
) -> None:
    current_toplevel = default_toplevel.resolve()

    check_mountpoint()

    entries = collect_entries(
        current_toplevel=current_toplevel,
    )

    default_entry = find_default_entry(entries)

    esp_root = EFI_SYS_MOUNT_POINT

    (esp_root / SPROUT_DIR).mkdir(
        parents=True,
        exist_ok=True,
    )
    (esp_root / NIXOS_DIR).mkdir(
        parents=True,
        exist_ok=True,
    )
    (esp_root / DRIVERS_DIR).mkdir(
        parents=True,
        exist_ok=True,
    )

    write_boot_files(entries)

    drivers = install_drivers()

    # Install the loader before publishing the new configuration. At this
    # point all boot artifacts needed by the new configuration already exist.
    install_sprout_binary()

    if EFI_INSTALL_AS_REMOVABLE:
        install_removable_loader()

    configuration = generate_sprout_config(
        entries,
        default_entry.identifier,
        drivers,
    )

    # Atomically replace sprout.toml only after all referenced files are present.
    atomic_write_text(
        esp_root / SPROUT_CONFIG,
        configuration,
    )

    if CAN_TOUCH_EFI_VARIABLES:
        install_nvram_entry()

    garbage_collect(
        entries,
        drivers,
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Install and update the Sprout bootloader for NixOS."
    )
    parser.add_argument(
        "default_config",
        metavar="DEFAULT-CONFIG",
        help="The NixOS toplevel that should be the default boot entry.",
    )

    args = parser.parse_args()

    try:
        install_bootloader(
            Path(args.default_config),
        )
    except subprocess.CalledProcessError as exc:
        command = " ".join(str(part) for part in exc.cmd)
        print(
            f"error: command failed: {command}",
            file=sys.stderr,
        )
        raise SystemExit(exc.returncode) from exc
    except (OSError, RuntimeError) as exc:
        print(
            f"error: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1) from exc
    finally:
        sync_filesystem(EFI_SYS_MOUNT_POINT)


if __name__ == "__main__":
    main()
