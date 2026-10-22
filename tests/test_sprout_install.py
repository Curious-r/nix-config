from __future__ import annotations

import errno
import hashlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path
from types import ModuleType
from typing import Any
from unittest.mock import Mock, call, patch


def load_sprout_installer(
    esp_mount: Path,
    sprout_binary: Path | None = None,
    drivers: dict[str, str] | None = None,
    timeout: int = 5,
    config_limit: int = 0,
    can_touch_efi: bool = False,
    removable: bool = False,
    entry_label: str = "NixOS Sprout",
    settings: dict[str, Any] | None = None,
) -> ModuleType:
    src_file = (
        Path(__file__).resolve().parent.parent
        / "modules"
        / "nixos"
        / "sprout-install.py"
    )
    code = src_file.read_text(encoding="utf-8")

    bin_path = sprout_binary or (esp_mount / "EFI" / "Sprout" / "sprout.efi")

    temp_settings = tempfile.NamedTemporaryFile(
        delete=False, suffix=".json", mode="w", encoding="utf-8"
    )
    json.dump(settings or {}, temp_settings)
    temp_settings.close()
    settings_file = Path(temp_settings.name)

    replacements = {
        "@python3@": sys.executable,
        "@efiSysMountPoint@": str(esp_mount),
        "@sproutBinary@": str(bin_path),
        "@nix@": "/nix",
        "@efibootmgr@": "/bin/efibootmgr",
        "@util-linux@": "/bin",
        "@timeout@": str(timeout),
        "@configurationLimit@": str(config_limit),
        "@canTouchEfiVariables@": "1" if can_touch_efi else "0",
        "@efiInstallAsRemovable@": "1" if removable else "0",
        "@firmwareEntryLabel@": json.dumps(entry_label),
        "@drivers@": json.dumps(drivers or {}),
        "@settingsFile@": str(settings_file),
    }

    for key, value in replacements.items():
        code = code.replace(key, value)

    module_name = f"sprout_install_test_{os.getpid()}_{id(esp_mount)}"
    spec = importlib.util.spec_from_loader(module_name, loader=None)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    exec(code, module.__dict__)
    return module


class SproutInstallRegressionTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir_obj = tempfile.TemporaryDirectory()
        self.temp_dir = Path(self.temp_dir_obj.name).resolve()
        self.esp_dir = self.temp_dir / "esp"
        self.esp_dir.mkdir(parents=True, exist_ok=True)

        self.old_cwd = Path.cwd()
        os.chdir(self.temp_dir)

        self.driver_src = self.temp_dir / "btrfs-driver.efi"
        self.driver_src.write_text("driver-initial")

        self.sprout_source = self.temp_dir / "source-sprout.efi"
        self.sprout_source.write_text("sprout-bin")

        self.drivers_config = {
            "btrfs": str(self.driver_src),
        }

        self.mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers=self.drivers_config,
        )

    def tearDown(self) -> None:
        os.chdir(self.old_cwd)
        self.temp_dir_obj.cleanup()

    def test_driver_path_stable_destination_for_same_identity(self) -> None:
        """Verify the same driver name and source identity produce a stable destination path."""
        path1 = self.mod.driver_path("btrfs", self.driver_src)
        path2 = self.mod.driver_path("btrfs", self.driver_src)

        self.assertEqual(path1, path2)
        self.assertEqual(path1.parent, self.mod.DRIVERS_DIR)
        self.assertTrue(path1.name.startswith("btrfs-"))
        self.assertTrue(path1.name.endswith(".efi"))

        expected_digest = hashlib.sha256(
            f"btrfs\n{self.driver_src.resolve()}".encode("utf-8")
        ).hexdigest()
        self.assertEqual(path1.name, f"btrfs-{expected_digest}.efi")

        # Symlink to the same source resolves to same canonical path and produces identical destination
        symlink_src = self.temp_dir / "btrfs-symlink.efi"
        symlink_src.symlink_to(self.driver_src)
        self.assertEqual(
            self.mod.driver_path("btrfs", symlink_src),
            path1,
        )

        # Different driver name produces different destination
        path_ext4 = self.mod.driver_path("ext4", self.driver_src)
        self.assertNotEqual(path1, path_ext4)

    def test_driver_update_produces_new_destination_and_leaves_older_file_untouched(
        self,
    ) -> None:
        """Verify updating a driver source identity produces a different destination and leaves older file untouched."""
        src_v1 = self.temp_dir / "driver-v1.efi"
        src_v1.write_text("content-v1")
        src_v2 = self.temp_dir / "driver-v2.efi"
        src_v2.write_text("content-v2")

        mod_v1 = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers={"btrfs": str(src_v1)},
        )
        installed_v1 = mod_v1.install_drivers()
        dest_v1 = self.esp_dir / installed_v1["btrfs"]
        self.assertTrue(dest_v1.exists())
        self.assertEqual(dest_v1.read_text(), "content-v1")

        mod_v2 = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers={"btrfs": str(src_v2)},
        )
        installed_v2 = mod_v2.install_drivers()
        dest_v2 = self.esp_dir / installed_v2["btrfs"]

        # Different destination path
        self.assertNotEqual(dest_v1, dest_v2)
        self.assertTrue(dest_v2.exists())
        self.assertEqual(dest_v2.read_text(), "content-v2")

        # Older driver file remains untouched
        self.assertTrue(dest_v1.exists())
        self.assertEqual(dest_v1.read_text(), "content-v1")

        # Verify no temporary files remain
        tmp_files = list((self.esp_dir / self.mod.DRIVERS_DIR).glob("*.tmp"))
        self.assertEqual(tmp_files, [])
        self.assertFalse((self.temp_dir / "EFI").exists())

    def test_driver_installation_failure_before_publication_leaves_config_and_drivers_unchanged(
        self,
    ) -> None:
        """Verify failure before publishing sprout.toml preserves prior config and referenced drivers."""
        src_v1 = self.temp_dir / "driver-v1.efi"
        src_v1.write_text("content-v1")
        src_v2 = self.temp_dir / "driver-v2.efi"
        src_v2.write_text("content-v2")

        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        kernel = self.temp_dir / "kernel.efi"
        kernel.write_text("kernel-bytes")
        dest_k = self.mod.artifact_path("kernel", kernel)
        entry = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS 1",
            sort_key="00000000000000000001",
            kernel=dest_k,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k,
                    source=kernel,
                    initrd_secrets=None,
                    generation=1,
                    critical=True,
                ),
            ),
            critical=True,
        )

        mod_v1 = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers={"btrfs": str(src_v1)},
        )
        with patch.object(mod_v1, "check_mountpoint"), patch.object(
            mod_v1, "collect_entries", return_value=[entry]
        ):
            mod_v1.install_bootloader(toplevel)

        config_path = self.esp_dir / mod_v1.SPROUT_CONFIG
        self.assertTrue(config_path.exists())
        initial_config = config_path.read_text()
        dest_v1 = self.esp_dir / mod_v1.driver_path("btrfs", src_v1)
        self.assertTrue(dest_v1.exists())
        self.assertEqual(dest_v1.read_text(), "content-v1")
        self.assertIn(dest_v1.name, initial_config)

        # Attempt to install v2, but fail after install_drivers and before atomic_write_text(sprout.toml)
        mod_v2 = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers={"btrfs": str(src_v2)},
        )
        with patch.object(mod_v2, "check_mountpoint"), patch.object(
            mod_v2, "collect_entries", return_value=[entry]
        ), patch.object(
            mod_v2,
            "install_sprout_binary",
            side_effect=RuntimeError("simulated failure after driver install"),
        ):
            with self.assertRaises(RuntimeError) as ctx:
                mod_v2.install_bootloader(toplevel)
            self.assertIn("simulated failure after driver install", str(ctx.exception))

        # Previously published sprout.toml remains untouched
        self.assertEqual(config_path.read_text(), initial_config)

        # Referenced v1 driver remains untouched
        self.assertTrue(dest_v1.exists())
        self.assertEqual(dest_v1.read_text(), "content-v1")

        # Newly copied v2 driver is rolled back because publication failed
        dest_v2 = self.esp_dir / mod_v2.driver_path("btrfs", src_v2)
        self.assertFalse(dest_v2.exists())
        self.assertNotIn(dest_v2.name, config_path.read_text())

    def test_garbage_collection_removes_obsolete_driver_versions_after_publication(
        self,
    ) -> None:
        """Verify garbage collection retains active driver and removes obsolete driver versions."""
        src_v1 = self.temp_dir / "driver-v1.efi"
        src_v1.write_text("content-v1")
        src_v2 = self.temp_dir / "driver-v2.efi"
        src_v2.write_text("content-v2")

        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        kernel = self.temp_dir / "kernel.efi"
        kernel.write_text("kernel-bytes")
        dest_k = self.mod.artifact_path("kernel", kernel)
        entry = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS 1",
            sort_key="00000000000000000001",
            kernel=dest_k,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k,
                    source=kernel,
                    initrd_secrets=None,
                    generation=1,
                    critical=True,
                ),
            ),
            critical=True,
        )

        mod_v1 = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers={"btrfs": str(src_v1)},
        )
        with patch.object(mod_v1, "check_mountpoint"), patch.object(
            mod_v1, "collect_entries", return_value=[entry]
        ):
            mod_v1.install_bootloader(toplevel)

        dest_v1 = self.esp_dir / mod_v1.driver_path("btrfs", src_v1)
        self.assertTrue(dest_v1.exists())

        # Successful publication of v2
        mod_v2 = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers={"btrfs": str(src_v2)},
        )
        with patch.object(mod_v2, "check_mountpoint"), patch.object(
            mod_v2, "collect_entries", return_value=[entry]
        ):
            mod_v2.install_bootloader(toplevel)

        dest_v2 = self.esp_dir / mod_v2.driver_path("btrfs", src_v2)
        self.assertTrue(dest_v2.exists())
        self.assertEqual(dest_v2.read_text(), "content-v2")

        # Obsolete v1 driver removed by garbage collection
        self.assertFalse(dest_v1.exists())

    def test_stale_unconfigured_driver_cleaned_up_by_garbage_collection(self) -> None:
        """Verify unconfigured stale drivers are removed by garbage collection."""
        stale_driver = self.esp_dir / self.mod.DRIVERS_DIR / "zfs-stale.efi"
        legacy_driver = self.esp_dir / self.mod.DRIVERS_DIR / "btrfs.efi"
        stale_driver.parent.mkdir(parents=True, exist_ok=True)
        stale_driver.write_text("stale-zfs")
        legacy_driver.write_text("legacy-btrfs")

        installed = self.mod.install_drivers()
        active_driver = self.esp_dir / installed["btrfs"]
        self.assertTrue(active_driver.exists())

        # Run garbage collection
        self.mod.garbage_collect([], installed)

        self.assertTrue(active_driver.exists(), "Active configured driver must be kept")
        self.assertFalse(
            stale_driver.exists(),
            "Stale unconfigured driver must be garbage collected",
        )
        self.assertFalse(
            legacy_driver.exists(),
            "Legacy unhashed driver must be garbage collected",
        )
        self.assertFalse((self.temp_dir / "EFI").exists())

    def test_driver_preflight_rejection_prevents_partial_installation(self) -> None:
        """Verify invalid driver name or missing source is rejected before any driver is copied."""
        # Case 1: Invalid driver name
        mod_bad_name = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers={"invalid/name": str(self.driver_src)},
        )
        with self.assertRaises(RuntimeError) as ctx:
            mod_bad_name.install_drivers()
        self.assertIn("invalid Sprout driver name", str(ctx.exception))
        self.assertEqual(
            list((self.esp_dir / self.mod.DRIVERS_DIR).glob("*.efi")),
            [],
        )

        # Case 2: One valid driver alongside a missing driver source
        valid_src = self.temp_dir / "valid-driver.efi"
        valid_src.write_text("valid-driver-content")
        missing_src = self.temp_dir / "missing-driver.efi"
        mod_missing = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers={
                "aaa_valid": str(valid_src),
                "bbb_missing": str(missing_src),
            },
        )
        with self.assertRaises(RuntimeError) as ctx2:
            mod_missing.install_drivers()
        self.assertIn("does not exist", str(ctx2.exception))
        # Ensure preflight aborted BEFORE copying aaa_valid
        self.assertEqual(
            list((self.esp_dir / self.mod.DRIVERS_DIR).glob("*.efi")),
            [],
        )

    def test_critical_initrd_failure_aborts(self) -> None:
        """Verify critical initrd failure raises RuntimeError without copying raw source."""
        bad_secrets = self.temp_dir / "bad-secrets.sh"
        bad_secrets.write_text("#!/bin/sh\nexit 1\n")
        bad_secrets.chmod(0o755)

        raw_initrd = self.temp_dir / "initrd-source.img"
        raw_initrd.write_text("raw-initrd-bytes")

        dest = self.mod.NIXOS_DIR / "initrd-critical.img"

        crit_artifact = self.mod.BootArtifact(
            destination=dest,
            source=raw_initrd,
            initrd_secrets=bad_secrets,
            generation=2,
            critical=True,
        )

        with self.assertRaises(RuntimeError) as ctx:
            self.mod.write_artifact(crit_artifact)

        self.assertIn("failed to append initrd secrets", str(ctx.exception))
        self.assertFalse(
            (self.esp_dir / dest).exists(),
            "Destination must not exist on failure",
        )
        self.assertFalse(
            (self.temp_dir / dest).exists(),
            "Must not write to working directory",
        )

    def test_older_generation_failure_no_fallback_and_entry_pruned(
        self,
    ) -> None:
        """Verify older generation failure does not install raw fallback and prunes entry."""
        bad_secrets = self.temp_dir / "bad-secrets.sh"
        bad_secrets.write_text("#!/bin/sh\nexit 1\n")
        bad_secrets.chmod(0o755)

        raw_initrd = self.temp_dir / "initrd-g1.img"
        raw_initrd.write_text("raw-initrd-g1")

        kernel_src = self.temp_dir / "kernel-g1.efi"
        kernel_src.write_text("kernel-g1")

        dest_initrd = self.mod.NIXOS_DIR / "initrd-g1.img"
        dest_kernel = self.mod.NIXOS_DIR / "kernel-g1.efi"

        art_kernel = self.mod.BootArtifact(
            destination=dest_kernel,
            source=kernel_src,
            initrd_secrets=None,
            generation=1,
            critical=False,
        )
        art_initrd = self.mod.BootArtifact(
            destination=dest_initrd,
            source=raw_initrd,
            initrd_secrets=bad_secrets,
            generation=1,
            critical=False,
        )

        # 1. Direct write_artifact test: returns False, raw source NOT copied
        success = self.mod.write_artifact(art_initrd)
        self.assertFalse(success)
        self.assertFalse(
            (self.esp_dir / dest_initrd).exists(),
            "Raw initrd must not be copied as a fallback",
        )
        self.assertFalse((self.temp_dir / dest_initrd).exists())

        # 2. write_boot_files prunes the entry referencing the unavailable artifact
        entry1 = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS Generation 1",
            sort_key="g1",
            kernel=dest_kernel,
            initrds=(dest_initrd,),
            options=(),
            artifacts=(art_kernel, art_initrd),
            critical=False,
        )

        valid_entries = self.mod.write_boot_files([entry1])
        self.assertEqual(
            valid_entries,
            [],
            "Entry referencing failed artifact must be omitted",
        )
        self.assertFalse((self.esp_dir / dest_initrd).exists())
        self.assertFalse((self.temp_dir / dest_initrd).exists())

    def test_existing_older_generation_artifact_retained(self) -> None:
        """Verify an existing older generation artifact is retained under reuse policy."""
        bad_secrets = self.temp_dir / "bad-secrets.sh"
        bad_secrets.write_text("#!/bin/sh\nexit 1\n")
        bad_secrets.chmod(0o755)

        raw_initrd = self.temp_dir / "initrd-g1.img"
        raw_initrd.write_text("raw-initrd-g1")

        dest_initrd = self.mod.NIXOS_DIR / "initrd-g1.img"
        phys_initrd = self.esp_dir / dest_initrd
        phys_initrd.parent.mkdir(parents=True, exist_ok=True)
        phys_initrd.write_text("pre-existing-valid-augmented-initrd")

        art_initrd = self.mod.BootArtifact(
            destination=dest_initrd,
            source=raw_initrd,
            initrd_secrets=bad_secrets,
            generation=1,
            critical=False,
        )

        success = self.mod.write_artifact(art_initrd)
        self.assertTrue(
            success, "Existing artifact should be reused successfully"
        )
        self.assertEqual(
            phys_initrd.read_text(), "pre-existing-valid-augmented-initrd"
        )
        self.assertFalse((self.temp_dir / dest_initrd).exists())

    def test_shared_failure_omits_all_affected_entries_and_preserves_default(
        self,
    ) -> None:
        """Verify shared artifact failure excludes all dependent entries and keeps default."""
        bad_secrets = self.temp_dir / "bad-secrets.sh"
        bad_secrets.write_text("#!/bin/sh\nexit 1\n")
        bad_secrets.chmod(0o755)

        good_secrets = self.temp_dir / "good-secrets.sh"
        good_secrets.write_text("#!/bin/sh\necho 'secrets' >> \"$1\"\n")
        good_secrets.chmod(0o755)

        # Gen 2: Current / Default (critical=True)
        k2 = self.temp_dir / "k2.efi"
        k2.write_text("k2")
        i2 = self.temp_dir / "i2.img"
        i2.write_text("i2")
        dest_k2 = self.mod.NIXOS_DIR / "k2.efi"
        dest_i2 = self.mod.NIXOS_DIR / "i2.img"
        art_k2 = self.mod.BootArtifact(dest_k2, k2, None, 2, True)
        art_i2 = self.mod.BootArtifact(dest_i2, i2, good_secrets, 2, True)
        entry2 = self.mod.BootEntry(
            "nixos-g2",
            "Gen 2",
            "g2",
            dest_k2,
            (dest_i2,),
            (),
            (art_k2, art_i2),
            True,
        )

        # Gen 1 Main and Specialisation sharing failed initrd
        k1 = self.temp_dir / "k1.efi"
        k1.write_text("k1")
        i1 = self.temp_dir / "i1.img"
        i1.write_text("i1")
        dest_k1 = self.mod.NIXOS_DIR / "k1.efi"
        dest_i1 = self.mod.NIXOS_DIR / "i1.img"
        art_k1 = self.mod.BootArtifact(dest_k1, k1, None, 1, False)
        art_i1 = self.mod.BootArtifact(dest_i1, i1, bad_secrets, 1, False)
        entry1_main = self.mod.BootEntry(
            "nixos-g1",
            "Gen 1",
            "g1",
            dest_k1,
            (dest_i1,),
            (),
            (art_k1, art_i1),
            False,
        )
        entry1_spec = self.mod.BootEntry(
            "nixos-g1-s-debug",
            "Gen 1 Debug",
            "g1-debug",
            dest_k1,
            (dest_i1,),
            (),
            (art_k1, art_i1),
            False,
        )

        # Gen 0 Older generation with pre-existing initrd
        k0 = self.temp_dir / "k0.efi"
        k0.write_text("k0")
        i0 = self.temp_dir / "i0.img"
        i0.write_text("i0")
        dest_k0 = self.mod.NIXOS_DIR / "k0.efi"
        dest_i0 = self.mod.NIXOS_DIR / "i0.img"
        phys_dest_i0 = self.esp_dir / dest_i0
        phys_dest_i0.parent.mkdir(parents=True, exist_ok=True)
        phys_dest_i0.write_text("existing-i0")
        art_k0 = self.mod.BootArtifact(dest_k0, k0, None, 0, False)
        art_i0 = self.mod.BootArtifact(dest_i0, i0, bad_secrets, 0, False)
        entry0 = self.mod.BootEntry(
            "nixos-g0",
            "Gen 0",
            "g0",
            dest_k0,
            (dest_i0,),
            (),
            (art_k0, art_i0),
            False,
        )

        valid_entries = self.mod.write_boot_files(
            [entry2, entry1_main, entry1_spec, entry0]
        )

        # Verify entry2 and entry0 are retained; entry1_main and entry1_spec both omitted
        self.assertEqual(
            [e.identifier for e in valid_entries], ["nixos-g2", "nixos-g0"]
        )

        # Verify sprout.toml contains only retained entries
        config = self.mod.generate_sprout_config(valid_entries, "nixos-g2", {})
        self.assertIn('[entries."nixos-g2"]', config)
        self.assertIn('[entries."nixos-g0"]', config)
        self.assertNotIn("nixos-g1", config)

        # Verify garbage collection cleans up orphaned k1 from omitted entry
        self.assertTrue((self.esp_dir / dest_k1).exists())
        self.mod.garbage_collect(valid_entries, {})
        self.assertFalse(
            (self.esp_dir / dest_k1).exists(),
            "Orphaned kernel should be garbage collected",
        )
        self.assertTrue((self.esp_dir / dest_k2).exists())
        self.assertTrue((self.esp_dir / dest_i2).exists())
        self.assertTrue((self.esp_dir / dest_k0).exists())
        self.assertTrue((self.esp_dir / dest_i0).exists())
        self.assertFalse((self.temp_dir / "EFI").exists())

    def test_empty_valid_entries_refuses_publication(self) -> None:
        """Verify that when no valid entries remain, publication is refused without writing sprout.toml."""
        bad_secrets = self.temp_dir / "bad-secrets.sh"
        bad_secrets.write_text("#!/bin/sh\nexit 1\n")
        bad_secrets.chmod(0o755)

        k1 = self.temp_dir / "k1.efi"
        k1.write_text("k1")
        i1 = self.temp_dir / "i1.img"
        i1.write_text("i1")
        dest_k1 = self.mod.NIXOS_DIR / "k1.efi"
        dest_i1 = self.mod.NIXOS_DIR / "i1.img"
        art_k1 = self.mod.BootArtifact(dest_k1, k1, None, 1, False)
        art_i1 = self.mod.BootArtifact(dest_i1, i1, bad_secrets, 1, False)
        entry1 = self.mod.BootEntry(
            "nixos-g1",
            "Gen 1",
            "g1",
            dest_k1,
            (dest_i1,),
            (),
            (art_k1, art_i1),
            False,
        )

        valid_entries = self.mod.write_boot_files([entry1])
        self.assertEqual(valid_entries, [])

        # If entries is empty, install_bootloader would raise
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        self.assertFalse(config_path.exists())
        self.assertFalse((self.temp_dir / self.mod.SPROUT_CONFIG).exists())

    def test_critical_initrd_launch_failure_aborts(self) -> None:
        """Verify critical initrd helper launch failure raises RuntimeError without copying raw source."""
        missing_secrets = self.temp_dir / "missing-secrets.sh"
        raw_initrd = self.temp_dir / "initrd-source.img"
        raw_initrd.write_text("raw-initrd-bytes")

        dest = self.mod.NIXOS_DIR / "initrd-critical-launch.img"

        crit_artifact = self.mod.BootArtifact(
            destination=dest,
            source=raw_initrd,
            initrd_secrets=missing_secrets,
            generation=2,
            critical=True,
        )

        with self.assertRaises(RuntimeError) as ctx:
            self.mod.write_artifact(crit_artifact)

        self.assertIn("failed to append initrd secrets", str(ctx.exception))
        self.assertFalse(
            (self.esp_dir / dest).exists(),
            "Destination must not exist on failure",
        )
        self.assertFalse((self.temp_dir / dest).exists())

    def test_preparation_filesystem_error_not_swallowed(self) -> None:
        """Verify filesystem error during initrd preparation is not swallowed as a helper failure."""
        missing_source = self.temp_dir / "nonexistent-source.img"
        dummy_secrets = self.temp_dir / "dummy-secrets.sh"
        dummy_secrets.write_text("#!/bin/sh\nexit 0\n")
        dummy_secrets.chmod(0o755)

        dest = self.mod.NIXOS_DIR / "initrd-nonexistent-src.img"

        older_artifact = self.mod.BootArtifact(
            destination=dest,
            source=missing_source,
            initrd_secrets=dummy_secrets,
            generation=1,
            critical=False,
        )

        # Unrelated filesystem errors during preparation must not be swallowed
        with self.assertRaises(FileNotFoundError):
            self.mod.write_initrd_with_secrets(older_artifact)

    def test_older_generation_launch_failure_no_fallback(self) -> None:
        """Verify older generation helper launch failure returns False and does not install raw fallback."""
        missing_secrets = self.temp_dir / "nonexistent-secrets.sh"
        raw_initrd = self.temp_dir / "initrd-g1.img"
        raw_initrd.write_text("raw-initrd-g1")

        dest = self.mod.NIXOS_DIR / "initrd-g1.img"

        art_initrd = self.mod.BootArtifact(
            destination=dest,
            source=raw_initrd,
            initrd_secrets=missing_secrets,
            generation=1,
            critical=False,
        )

        success = self.mod.write_artifact(art_initrd)
        self.assertFalse(success)
        self.assertFalse(
            (self.esp_dir / dest).exists(),
            "Raw initrd must not be copied as a fallback",
        )
        self.assertFalse((self.temp_dir / dest).exists())

    def test_install_bootloader_critical_secrets_failure_aborts_without_creating_or_replacing_config(
        self,
    ) -> None:
        """Verify critical secrets-helper failure aborts installation without replacing or creating sprout.toml."""
        bad_secrets = self.temp_dir / "bad-secrets.sh"
        bad_secrets.write_text("#!/bin/sh\nexit 1\n")
        bad_secrets.chmod(0o755)

        k2 = self.temp_dir / "k2.efi"
        k2.write_text("k2")
        i2 = self.temp_dir / "i2.img"
        i2.write_text("i2")
        dest_k2 = self.mod.NIXOS_DIR / "k2.efi"
        dest_i2 = self.mod.NIXOS_DIR / "i2.img"
        art_k2 = self.mod.BootArtifact(dest_k2, k2, None, 2, True)
        art_i2 = self.mod.BootArtifact(dest_i2, i2, bad_secrets, 2, True)
        entry_default = self.mod.BootEntry(
            "nixos-g2",
            "Gen 2",
            "g2",
            dest_k2,
            (dest_i2,),
            (),
            (art_k2, art_i2),
            True,
        )

        config_path = self.esp_dir / self.mod.SPROUT_CONFIG

        # Case 1: Fresh install (sprout.toml does not exist). Must not be created on failure.
        self.assertFalse(config_path.exists())
        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry_default]
        ):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.install_bootloader(self.temp_dir)
            self.assertIn("failed to append initrd secrets", str(ctx.exception))

        self.assertFalse(
            config_path.exists(),
            "sprout.toml must not be created when critical entry fails",
        )

        # Case 2: Update install (sprout.toml already exists). Must not be replaced on failure.
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text("version = 1\n# pre-existing-valid-config\n")

        # Also test with a helper launch failure (nonexistent executable)
        missing_secrets = self.temp_dir / "missing-secrets.sh"
        art_i2_launch_fail = self.mod.BootArtifact(
            dest_i2, i2, missing_secrets, 2, True
        )
        entry_default_launch_fail = self.mod.BootEntry(
            "nixos-g2",
            "Gen 2",
            "g2",
            dest_k2,
            (dest_i2,),
            (),
            (art_k2, art_i2_launch_fail),
            True,
        )

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod,
            "collect_entries",
            return_value=[entry_default_launch_fail],
        ):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.install_bootloader(self.temp_dir)
            self.assertIn("failed to append initrd secrets", str(ctx.exception))

        self.assertEqual(
            config_path.read_text(),
            "version = 1\n# pre-existing-valid-config\n",
            "Existing sprout.toml must remain untouched on failure",
        )

    def test_install_bootloader_all_entries_pruned_leaves_config_unchanged(
        self,
    ) -> None:
        """Verify that if all entries are pruned, the installer refuses publication and leaves existing configuration unchanged."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text("version = 1\n# previous-published-sprout-configuration\n")

        # Entry 1: older generation whose helper exits 1
        bad_secrets = self.temp_dir / "bad-secrets.sh"
        bad_secrets.write_text("#!/bin/sh\nexit 1\n")
        bad_secrets.chmod(0o755)

        k1 = self.temp_dir / "k1.efi"
        k1.write_text("k1")
        i1 = self.temp_dir / "i1.img"
        i1.write_text("i1")
        dest_k1 = self.mod.NIXOS_DIR / "k1.efi"
        dest_i1 = self.mod.NIXOS_DIR / "i1.img"
        art_k1 = self.mod.BootArtifact(dest_k1, k1, None, 1, False)
        art_i1 = self.mod.BootArtifact(dest_i1, i1, bad_secrets, 1, False)
        entry1 = self.mod.BootEntry(
            "nixos-g1",
            "Gen 1",
            "g1",
            dest_k1,
            (dest_i1,),
            (),
            (art_k1, art_i1),
            False,
        )

        # Entry 0: older generation whose helper fails to launch
        missing_secrets = self.temp_dir / "missing-secrets.sh"
        k0 = self.temp_dir / "k0.efi"
        k0.write_text("k0")
        i0 = self.temp_dir / "i0.img"
        i0.write_text("i0")
        dest_k0 = self.mod.NIXOS_DIR / "k0.efi"
        dest_i0 = self.mod.NIXOS_DIR / "i0.img"
        art_k0 = self.mod.BootArtifact(dest_k0, k0, None, 0, False)
        art_i0 = self.mod.BootArtifact(dest_i0, i0, missing_secrets, 0, False)
        entry0 = self.mod.BootEntry(
            "nixos-g0",
            "Gen 0",
            "g0",
            dest_k0,
            (dest_i0,),
            (),
            (art_k0, art_i0),
            False,
        )

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry1, entry0]
        ):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.install_bootloader(self.temp_dir)
            self.assertIn(
                "no valid boot entries remain; refusing to publish configuration",
                str(ctx.exception),
            )

        self.assertEqual(
            config_path.read_text(),
            "version = 1\n# previous-published-sprout-configuration\n",
            "Existing configuration must be left unchanged when all entries are pruned",
        )

    def test_install_bootloader_older_generation_helper_launch_failure(
        self,
    ) -> None:
        """Add a test for an older-generation helper launch failure that confirms the affected entry is omitted while the current/default entry remains valid."""
        good_secrets = self.temp_dir / "good-secrets.sh"
        good_secrets.write_text("#!/bin/sh\necho 'secrets' >> \"$1\"\n")
        good_secrets.chmod(0o755)

        # Current/default entry (critical=True)
        kd = self.temp_dir / "kd.efi"
        kd.write_text("kd")
        id_src = self.temp_dir / "id.img"
        id_src.write_text("id")
        dest_kd = self.mod.NIXOS_DIR / "kd.efi"
        dest_id = self.mod.NIXOS_DIR / "id.img"
        art_kd = self.mod.BootArtifact(dest_kd, kd, None, 2, True)
        art_id = self.mod.BootArtifact(dest_id, id_src, good_secrets, 2, True)
        entry_default = self.mod.BootEntry(
            "nixos-g2",
            "Gen 2",
            "g2",
            dest_kd,
            (dest_id,),
            (),
            (art_kd, art_id),
            True,
        )

        # Older generation entry (critical=False) with launch failure (missing helper file)
        missing_helper = self.temp_dir / "missing-helper.sh"
        ko = self.temp_dir / "ko.efi"
        ko.write_text("ko")
        io_src = self.temp_dir / "io.img"
        io_src.write_text("io")
        dest_ko = self.mod.NIXOS_DIR / "ko.efi"
        dest_io = self.mod.NIXOS_DIR / "io.img"
        art_ko = self.mod.BootArtifact(dest_ko, ko, None, 1, False)
        art_io = self.mod.BootArtifact(dest_io, io_src, missing_helper, 1, False)
        entry_older = self.mod.BootEntry(
            "nixos-g1",
            "Gen 1",
            "g1",
            dest_ko,
            (dest_io,),
            (),
            (art_ko, art_io),
            False,
        )

        config_path = self.esp_dir / self.mod.SPROUT_CONFIG

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod,
            "collect_entries",
            return_value=[entry_default, entry_older],
        ):
            self.mod.install_bootloader(self.temp_dir)

        # Verify sprout.toml was created
        self.assertTrue(config_path.exists())
        config_text = config_path.read_text()

        # Confirm default entry is present and configured as default
        self.assertIn('[entries."nixos-g2"]', config_text)
        self.assertIn('default-entry = "nixos-g2"', config_text)

        # Confirm older entry with launch failure is omitted
        self.assertNotIn("nixos-g1", config_text)

        # Confirm destination files:
        # Default entry artifacts exist
        self.assertTrue((self.esp_dir / dest_kd).exists())
        self.assertTrue((self.esp_dir / dest_id).exists())
        # Older entry initrd was NOT created
        self.assertFalse((self.esp_dir / dest_io).exists())
        # Older entry kernel was cleaned up by garbage collection
        self.assertFalse((self.esp_dir / dest_ko).exists())
        self.assertFalse((self.temp_dir / "EFI").exists())

    def test_extra_initrd_recognized_on_esp_and_preserves_order(self) -> None:
        """Verify extra-initrds on ESP are recognized, ordered after main initrd, and not collected."""
        extra_rel = Path("extra-initrd.img")
        extra_esp = self.esp_dir / extra_rel
        extra_esp.write_text("extra-initrd-content")

        k = self.temp_dir / "k.efi"
        k.write_text("kernel-binary")
        i = self.temp_dir / "i.img"
        i.write_text("main-initrd-binary")

        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)

        bootspec = self.mod.BootSpec(
            init=Path("/nix/store/dummy-init"),
            toplevel=toplevel,
            label="NixOS 24.11",
            kernel=k,
            initrd=i,
            initrd_secrets=None,
            extra_initrds=(extra_rel,),
            kernel_params=("console=tty0",),
            specialisations={},
        )

        entry = self.mod.prepare_entry(
            profile=None,
            generation=1,
            specialisation=None,
            bootspec=bootspec,
            current_toplevel=toplevel,
        )
        self.assertIsNotNone(entry)
        assert entry is not None

        # Verify entry.initrds order: main initrd first, then extra initrd
        self.assertEqual(len(entry.initrds), 2)
        main_initrd_dest = entry.initrds[0]
        self.assertEqual(entry.initrds[1], extra_rel)

        # Artifacts should only include kernel and main initrd (extra initrd is already on ESP)
        self.assertEqual(len(entry.artifacts), 2)
        artifact_dests = [art.destination for art in entry.artifacts]
        self.assertIn(entry.kernel, artifact_dests)
        self.assertIn(main_initrd_dest, artifact_dests)
        self.assertNotIn(extra_rel, artifact_dests)

        # Install bootloader
        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry]
        ):
            self.mod.install_bootloader(toplevel)

        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        self.assertTrue(config_path.exists())
        config_text = config_path.read_text()

        # Verify linux-initrd-chain has main initrd followed by extra initrd
        expected_main_uefi = self.mod.uefi_path(main_initrd_dest)
        expected_extra_uefi = self.mod.uefi_path(extra_rel)
        expected_chain = f"chainload.linux-initrd-chain = {self.mod.array_toml([expected_main_uefi, expected_extra_uefi])}"
        self.assertIn(expected_chain, config_text)

        # Verify extra initrd still exists on ESP and was not deleted by GC
        self.assertTrue(extra_esp.exists())
        self.assertEqual(extra_esp.read_text(), "extra-initrd-content")

        # Verify no files were created in working directory
        self.assertFalse((self.temp_dir / "EFI").exists())
        self.assertFalse((self.temp_dir / extra_rel).exists())

    def test_missing_extra_initrd_critical_aborts_without_publishing(self) -> None:
        """Verify missing extra initrd for critical entry aborts installation without modifying config."""
        extra_rel = Path("missing-extra.img")
        self.assertFalse((self.esp_dir / extra_rel).exists())

        k = self.temp_dir / "k.efi"
        k.write_text("kernel-binary")
        i = self.temp_dir / "i.img"
        i.write_text("main-initrd-binary")

        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)

        bootspec = self.mod.BootSpec(
            init=Path("/nix/store/dummy-init"),
            toplevel=toplevel,
            label="NixOS 24.11",
            kernel=k,
            initrd=i,
            initrd_secrets=None,
            extra_initrds=(extra_rel,),
            kernel_params=(),
            specialisations={},
        )

        # 1. prepare_entry with critical=True raises RuntimeError
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.prepare_entry(
                profile=None,
                generation=1,
                specialisation=None,
                bootspec=bootspec,
                current_toplevel=toplevel,
            )
        self.assertIn("references missing extra initrd on ESP", str(ctx.exception))

        # 2. Existing sprout.toml must remain untouched
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text("version = 1\n# pre-existing-config\n")

        dest_k = self.mod.NIXOS_DIR / "k.efi"
        dest_i = self.mod.NIXOS_DIR / "i.img"
        art_k = self.mod.BootArtifact(dest_k, k, None, 1, True)
        art_i = self.mod.BootArtifact(dest_i, i, None, 1, True)
        entry = self.mod.BootEntry(
            "nixos-g1",
            "Gen 1",
            "g1",
            dest_k,
            (dest_i, extra_rel),
            (),
            (art_k, art_i),
            True,
        )

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry]
        ):
            with self.assertRaises(RuntimeError) as ctx2:
                self.mod.install_bootloader(self.temp_dir)
            self.assertIn("missing initrd on ESP", str(ctx2.exception))

        self.assertEqual(config_path.read_text(), "version = 1\n# pre-existing-config\n")
        self.assertFalse((self.temp_dir / "EFI").exists())

    def test_missing_extra_initrd_older_generation_pruned(self) -> None:
        """Verify missing extra initrd for older generation prunes only affected entry."""
        # Default generation 2: valid
        k2 = self.temp_dir / "k2.efi"
        k2.write_text("k2")
        i2 = self.temp_dir / "i2.img"
        i2.write_text("i2")
        dest_k2 = self.mod.NIXOS_DIR / "k2.efi"
        dest_i2 = self.mod.NIXOS_DIR / "i2.img"
        art_k2 = self.mod.BootArtifact(dest_k2, k2, None, 2, True)
        art_i2 = self.mod.BootArtifact(dest_i2, i2, None, 2, True)
        entry_default = self.mod.BootEntry(
            "nixos-g2",
            "Gen 2",
            "g2",
            dest_k2,
            (dest_i2,),
            (),
            (art_k2, art_i2),
            True,
        )

        # Older generation 1: references missing extra initrd
        missing_extra = Path("missing-extra-g1.img")
        k1 = self.temp_dir / "k1.efi"
        k1.write_text("k1")
        i1 = self.temp_dir / "i1.img"
        i1.write_text("i1")
        dest_k1 = self.mod.NIXOS_DIR / "k1.efi"
        dest_i1 = self.mod.NIXOS_DIR / "i1.img"
        art_k1 = self.mod.BootArtifact(dest_k1, k1, None, 1, False)
        art_i1 = self.mod.BootArtifact(dest_i1, i1, None, 1, False)
        entry_older = self.mod.BootEntry(
            "nixos-g1",
            "Gen 1",
            "g1",
            dest_k1,
            (dest_i1, missing_extra),
            (),
            (art_k1, art_i1),
            False,
        )

        config_path = self.esp_dir / self.mod.SPROUT_CONFIG

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod,
            "collect_entries",
            return_value=[entry_default, entry_older],
        ):
            self.mod.install_bootloader(self.temp_dir)

        self.assertTrue(config_path.exists())
        config_text = config_path.read_text()

        # Default entry published
        self.assertIn('[entries."nixos-g2"]', config_text)
        self.assertIn('default-entry = "nixos-g2"', config_text)

        # Older entry omitted
        self.assertNotIn("nixos-g1", config_text)

        # Default artifacts exist on ESP
        self.assertTrue((self.esp_dir / dest_k2).exists())
        self.assertTrue((self.esp_dir / dest_i2).exists())

        # Older artifacts were cleaned up by garbage collection
        self.assertFalse((self.esp_dir / dest_k1).exists())
        self.assertFalse((self.esp_dir / dest_i1).exists())
        self.assertFalse((self.temp_dir / "EFI").exists())

    def test_invalid_extra_initrd_escaping_esp_rejected(self) -> None:
        """Verify invalid extra initrd path attempting to escape ESP is rejected safely."""
        k = self.temp_dir / "k.efi"
        k.write_text("k")
        i = self.temp_dir / "i.img"
        i.write_text("i")

        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        other_toplevel = self.temp_dir / "other-toplevel"
        other_toplevel.mkdir(parents=True, exist_ok=True)

        for bad_path in (
            Path("../escape.img"),
            Path("../../etc/passwd"),
            Path("/absolute/path.img"),
            Path("/EFI/test.img"),
        ):
            bootspec = self.mod.BootSpec(
                init=Path("/nix/store/dummy-init"),
                toplevel=toplevel,
                label="NixOS 24.11",
                kernel=k,
                initrd=i,
                initrd_secrets=None,
                extra_initrds=(bad_path,),
                kernel_params=(),
                specialisations={},
            )

            # 1. Critical entry raises RuntimeError
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.prepare_entry(
                    profile=None,
                    generation=1,
                    specialisation=None,
                    bootspec=bootspec,
                    current_toplevel=toplevel,
                )
            self.assertIn("not a valid ESP-relative path", str(ctx.exception))

            # 2. Non-critical entry is safely skipped (returns None)
            skipped = self.mod.prepare_entry(
                profile=None,
                generation=1,
                specialisation=None,
                bootspec=bootspec,
                current_toplevel=other_toplevel,
            )
            self.assertIsNone(skipped)

    def test_separate_esp_and_working_directory_no_parallel_artifacts(
        self,
    ) -> None:
        """Verify full installation when ESP is a distinct subdirectory does not leak files to CWD."""
        k = self.temp_dir / "k.efi"
        k.write_text("k")
        i = self.temp_dir / "i.img"
        i.write_text("i")

        extra_initrd = Path("EFI/vendor/addon.img")
        (self.esp_dir / extra_initrd).parent.mkdir(parents=True, exist_ok=True)
        (self.esp_dir / extra_initrd).write_text("extra-addon")

        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)

        bootspec = self.mod.BootSpec(
            init=Path("/nix/store/dummy-init"),
            toplevel=toplevel,
            label="NixOS 24.11",
            kernel=k,
            initrd=i,
            initrd_secrets=None,
            extra_initrds=(extra_initrd,),
            kernel_params=("quiet",),
            specialisations={},
        )

        entry = self.mod.prepare_entry(
            profile=None,
            generation=1,
            specialisation=None,
            bootspec=bootspec,
            current_toplevel=toplevel,
        )
        self.assertIsNotNone(entry)
        assert entry is not None

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry]
        ):
            self.mod.install_bootloader(toplevel)

        # Sprout files exist on ESP
        self.assertTrue((self.esp_dir / self.mod.SPROUT_CONFIG).exists())
        self.assertTrue((self.esp_dir / self.mod.SPROUT_BINARY).exists())
        self.assertTrue((self.esp_dir / entry.kernel).exists())
        self.assertTrue((self.esp_dir / entry.initrds[0]).exists())
        self.assertTrue((self.esp_dir / entry.initrds[1]).exists())
        driver_dest = self.mod.driver_path("btrfs", self.driver_src)
        self.assertTrue(
            (self.esp_dir / driver_dest).exists()
        )

        # CWD must contain NO boot artifacts / directories
        self.assertFalse((self.temp_dir / "EFI").exists())
        self.assertFalse((self.temp_dir / "sprout.toml").exists())
        self.assertFalse((self.temp_dir / entry.kernel).exists())
        self.assertFalse((self.temp_dir / entry.initrds[0]).exists())

    def test_kernel_params_retained_in_order_with_init_first(self) -> None:
        """Verify kernel parameters retain order and are emitted with init=<path> first."""
        k = self.temp_dir / "k.efi"
        k.write_text("k")
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)

        params = (
            "console=ttyS0,115200",
            "earlycon",
            "loglevel=4",
            "rootflags=subvol=@root",
            "systemd.debug_shell=1",
        )

        bootspec = self.mod.BootSpec(
            init=Path("/nix/store/custom-init-script"),
            toplevel=toplevel,
            label="NixOS 24.11",
            kernel=k,
            initrd=None,
            initrd_secrets=None,
            extra_initrds=(),
            kernel_params=params,
            specialisations={},
        )

        entry = self.mod.prepare_entry(
            profile=None,
            generation=1,
            specialisation=None,
            bootspec=bootspec,
            current_toplevel=toplevel,
        )
        self.assertIsNotNone(entry)
        assert entry is not None

        expected_options = (
            "init=/nix/store/custom-init-script",
            *params,
        )
        self.assertEqual(entry.options, expected_options)

        config = self.mod.generate_sprout_config([entry], entry.identifier, {})
        expected_options_toml = (
            f"chainload.options = {self.mod.array_toml(list(expected_options))}"
        )
        self.assertIn(expected_options_toml, config)

    def test_single_main_initrd_emits_linux_initrd(self) -> None:
        """Verify a single main initrd is emitted as chainload.linux-initrd without chain."""
        dest_k = self.mod.NIXOS_DIR / "k.efi"
        dest_i = self.mod.NIXOS_DIR / "i.img"
        entry = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS Gen 1",
            sort_key="00000000000000000001",
            kernel=dest_k,
            initrds=(dest_i,),
            options=("init=/nix/store/init",),
            artifacts=(),
            critical=True,
        )

        config = self.mod.generate_sprout_config([entry], entry.identifier, {})
        expected_initrd_toml = (
            f"chainload.linux-initrd = {self.mod.quote_toml(self.mod.uefi_path(dest_i))}"
        )
        self.assertIn(expected_initrd_toml, config)
        self.assertNotIn("chainload.linux-initrd-chain", config)

    def test_main_and_extra_initrd_chain_emits_ordered_chain(self) -> None:
        """Verify main plus extra initrds emit chainload.linux-initrd-chain in correct order."""
        dest_k = self.mod.NIXOS_DIR / "k.efi"
        dest_main = self.mod.NIXOS_DIR / "main-initrd.img"
        extra1 = Path("EFI/vendor/extra1.img")
        extra2 = Path("extra2.img")

        entry = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS Gen 1",
            sort_key="00000000000000000001",
            kernel=dest_k,
            initrds=(dest_main, extra1, extra2),
            options=("init=/nix/store/init",),
            artifacts=(),
            critical=True,
        )

        config = self.mod.generate_sprout_config([entry], entry.identifier, {})
        expected_chain_toml = (
            "chainload.linux-initrd-chain = "
            + self.mod.array_toml(
                [
                    self.mod.uefi_path(dest_main),
                    self.mod.uefi_path(extra1),
                    self.mod.uefi_path(extra2),
                ]
            )
        )
        self.assertIn(expected_chain_toml, config)
        self.assertNotIn("chainload.linux-initrd = ", config)

    def test_specialisation_produces_separate_entry_with_own_artifacts(
        self,
    ) -> None:
        """Verify a specialisation produces its own boot entry with its own kernel, initrd, and options."""
        k_main = self.temp_dir / "k-main.efi"
        k_main.write_text("k-main")
        i_main = self.temp_dir / "i-main.img"
        i_main.write_text("i-main")
        toplevel_main = self.temp_dir / "toplevel-main"
        toplevel_main.mkdir(parents=True, exist_ok=True)

        k_spec = self.temp_dir / "k-spec.efi"
        k_spec.write_text("k-spec")
        i_spec = self.temp_dir / "i-spec.img"
        i_spec.write_text("i-spec")
        toplevel_spec = self.temp_dir / "toplevel-spec"
        toplevel_spec.mkdir(parents=True, exist_ok=True)

        spec_bootspec = self.mod.BootSpec(
            init=Path("/nix/store/spec-init"),
            toplevel=toplevel_spec,
            label="NixOS 24.11 (Debug)",
            kernel=k_spec,
            initrd=i_spec,
            initrd_secrets=None,
            extra_initrds=(),
            kernel_params=("debug", "systemd.log_level=debug"),
            specialisations={},
        )

        main_bootspec = self.mod.BootSpec(
            init=Path("/nix/store/main-init"),
            toplevel=toplevel_main,
            label="NixOS 24.11",
            kernel=k_main,
            initrd=i_main,
            initrd_secrets=None,
            extra_initrds=(),
            kernel_params=("quiet",),
            specialisations={"debug": spec_bootspec},
        )

        with patch.object(
            self.mod,
            "get_generations",
            return_value=[self.mod.SystemIdentifier(None, 1)],
        ), patch.object(
            self.mod, "get_profiles", return_value=[]
        ), patch.object(
            self.mod, "load_bootspec", return_value=main_bootspec
        ):
            entries = self.mod.collect_entries(current_toplevel=toplevel_main)

        self.assertEqual(len(entries), 2)
        entry_main = next(e for e in entries if e.identifier == "nixos-g1")
        expected_spec_id = self.mod.entry_identifier(None, 1, "debug")
        entry_spec = next(
            e for e in entries if e.identifier == expected_spec_id
        )

        # Main entry uses its own kernel, initrd, options
        self.assertEqual(
            entry_main.options, ("init=/nix/store/main-init", "quiet")
        )
        self.assertEqual(len(entry_main.initrds), 1)
        self.assertTrue(entry_main.critical)

        # Specialisation entry uses its own kernel, initrd, options
        self.assertEqual(
            entry_spec.options,
            ("init=/nix/store/spec-init", "debug", "systemd.log_level=debug"),
        )
        self.assertEqual(len(entry_spec.initrds), 1)
        # Distinct artifacts from main
        self.assertNotEqual(entry_main.kernel, entry_spec.kernel)
        self.assertNotEqual(entry_main.initrds[0], entry_spec.initrds[0])
        self.assertFalse(entry_spec.critical)

        # Check serialized config
        config = self.mod.generate_sprout_config(
            entries, entry_main.identifier, {}
        )
        self.assertIn('[entries."nixos-g1"]', config)
        self.assertIn(f'[entries."{expected_spec_id}"]', config)
        self.assertIn('[actions."nixos-g1"]', config)
        self.assertIn(f'[actions."{expected_spec_id}"]', config)
        self.assertIn(
            f"chainload.path = {self.mod.quote_toml(self.mod.uefi_path(entry_main.kernel))}",
            config,
        )
        self.assertIn(
            f"chainload.path = {self.mod.quote_toml(self.mod.uefi_path(entry_spec.kernel))}",
            config,
        )

    def test_bootspec_without_specialisations_produces_only_main_entry(
        self,
    ) -> None:
        """Verify a BootSpec without specialisations produces only the main entry."""
        k = self.temp_dir / "k.efi"
        k.write_text("k")
        i = self.temp_dir / "i.img"
        i.write_text("i")
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)

        bootspec = self.mod.BootSpec(
            init=Path("/nix/store/init"),
            toplevel=toplevel,
            label="NixOS 24.11",
            kernel=k,
            initrd=i,
            initrd_secrets=None,
            extra_initrds=(),
            kernel_params=(),
            specialisations={},
        )

        with patch.object(
            self.mod,
            "get_generations",
            return_value=[self.mod.SystemIdentifier(None, 1)],
        ), patch.object(
            self.mod, "get_profiles", return_value=[]
        ), patch.object(
            self.mod, "load_bootspec", return_value=bootspec
        ):
            entries = self.mod.collect_entries(current_toplevel=toplevel)

        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0].identifier, "nixos-g1")

    def test_bootspec_without_devicetree_supported(self) -> None:
        """Verify BootSpec without devicetree request remains supported."""
        k = self.temp_dir / "k.efi"
        k.write_text("k")
        i = self.temp_dir / "i.img"
        i.write_text("i")
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)

        bootspec = self.mod.BootSpec(
            init=Path("/nix/store/init"),
            toplevel=toplevel,
            label="NixOS 24.11",
            kernel=k,
            initrd=i,
            initrd_secrets=None,
            extra_initrds=(),
            kernel_params=(),
            specialisations={},
            devicetree=None,
        )

        entry = self.mod.prepare_entry(
            profile=None,
            generation=1,
            specialisation=None,
            bootspec=bootspec,
            current_toplevel=toplevel,
        )
        self.assertIsNotNone(entry)

    def test_devicetree_critical_entry_aborts_without_creating_or_replacing_config(
        self,
    ) -> None:
        """Verify critical entry requesting devicetree aborts installation without creating or replacing sprout.toml."""
        k = self.temp_dir / "k.efi"
        k.write_text("k")
        i = self.temp_dir / "i.img"
        i.write_text("i")
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)

        bootspec = self.mod.BootSpec(
            init=Path("/nix/store/init"),
            toplevel=toplevel,
            label="NixOS 24.11",
            kernel=k,
            initrd=i,
            initrd_secrets=None,
            extra_initrds=(),
            kernel_params=(),
            specialisations={},
            devicetree=Path("/nix/store/dummy.dtb"),
        )

        config_path = self.esp_dir / self.mod.SPROUT_CONFIG

        # 1. Fresh install: sprout.toml does not exist
        self.assertFalse(config_path.exists())
        with patch.object(
            self.mod,
            "get_generations",
            return_value=[self.mod.SystemIdentifier(None, 1)],
        ), patch.object(
            self.mod, "get_profiles", return_value=[]
        ), patch.object(
            self.mod, "load_bootspec", return_value=bootspec
        ), patch.object(
            self.mod, "check_mountpoint"
        ):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.install_bootloader(toplevel)
            self.assertIn("requests devicetree", str(ctx.exception))
            self.assertIn(
                "devicetree is not supported by Sprout", str(ctx.exception)
            )

        self.assertFalse(
            config_path.exists(),
            "sprout.toml must not be created when devicetree fails",
        )

        # 2. Existing config: sprout.toml already exists
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text("pre-existing-valid-config")

        with patch.object(
            self.mod,
            "get_generations",
            return_value=[self.mod.SystemIdentifier(None, 1)],
        ), patch.object(
            self.mod, "get_profiles", return_value=[]
        ), patch.object(
            self.mod, "load_bootspec", return_value=bootspec
        ), patch.object(
            self.mod, "check_mountpoint"
        ):
            with self.assertRaises(RuntimeError) as ctx2:
                self.mod.install_bootloader(toplevel)
            self.assertIn("requests devicetree", str(ctx2.exception))

        self.assertEqual(
            config_path.read_text(),
            "pre-existing-valid-config",
            "Existing sprout.toml must remain untouched",
        )

    def test_devicetree_older_generation_skipped_and_valid_entries_retained(
        self,
    ) -> None:
        """Verify older generation requesting devicetree is skipped while valid entries are retained."""
        k2 = self.temp_dir / "k2.efi"
        k2.write_text("k2")
        i2 = self.temp_dir / "i2.img"
        i2.write_text("i2")
        toplevel2 = self.temp_dir / "toplevel2"
        toplevel2.mkdir(parents=True, exist_ok=True)

        k1 = self.temp_dir / "k1.efi"
        k1.write_text("k1")
        i1 = self.temp_dir / "i1.img"
        i1.write_text("i1")
        toplevel1 = self.temp_dir / "toplevel1"
        toplevel1.mkdir(parents=True, exist_ok=True)

        # Default gen 2: valid, no devicetree
        bootspec2 = self.mod.BootSpec(
            init=Path("/nix/store/init2"),
            toplevel=toplevel2,
            label="NixOS Gen 2",
            kernel=k2,
            initrd=i2,
            initrd_secrets=None,
            extra_initrds=(),
            kernel_params=(),
            specialisations={},
            devicetree=None,
        )

        # Older gen 1: requests devicetree
        bootspec1 = self.mod.BootSpec(
            init=Path("/nix/store/init1"),
            toplevel=toplevel1,
            label="NixOS Gen 1",
            kernel=k1,
            initrd=i1,
            initrd_secrets=None,
            extra_initrds=(),
            kernel_params=(),
            specialisations={},
            devicetree=Path("/nix/store/dtb1.dtb"),
        )

        def mock_load(profile: str | None, generation: int) -> Any:
            return bootspec2 if generation == 2 else bootspec1

        with patch.object(
            self.mod,
            "get_generations",
            return_value=[
                self.mod.SystemIdentifier(None, 2),
                self.mod.SystemIdentifier(None, 1),
            ],
        ), patch.object(
            self.mod, "get_profiles", return_value=[]
        ), patch.object(
            self.mod, "load_bootspec", side_effect=mock_load
        ), patch.object(
            self.mod, "check_mountpoint"
        ):
            self.mod.install_bootloader(toplevel2)

        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        self.assertTrue(config_path.exists())
        config_text = config_path.read_text()

        # Gen 2 is present and is default
        self.assertIn('[entries."nixos-g2"]', config_text)
        self.assertIn('default-entry = "nixos-g2"', config_text)

        # Gen 1 with devicetree was skipped
        self.assertNotIn("nixos-g1", config_text)

        # Gen 2 artifacts installed
        self.assertTrue((self.esp_dir / self.mod.NIXOS_DIR).exists())
        # Gen 1 kernel was not installed
        self.assertFalse(
            (self.esp_dir / self.mod.artifact_path("kernel", k1)).exists()
        )

    def test_profile_identifier_collision_resistance_distinct_slug_normalization(
        self,
    ) -> None:
        """Verify that profiles with identical normalized slugs produce distinct identifiers."""
        id1 = self.mod.entry_identifier("foo bar", 1, None)
        id2 = self.mod.entry_identifier("foo+bar", 1, None)

        self.assertNotEqual(id1, id2)
        self.assertTrue(id1.startswith("nixos-p-foo-bar-"))
        self.assertTrue(id2.startswith("nixos-p-foo-bar-"))
        self.assertTrue(id1.endswith("-g1"))
        self.assertTrue(id2.endswith("-g1"))

        # Deterministic generation across calls
        self.assertEqual(id1, self.mod.entry_identifier("foo bar", 1, None))

        # Default system profile retains nixos-gN format
        default_id = self.mod.entry_identifier(None, 1, None)
        self.assertEqual(default_id, "nixos-g1")

        # Specialisations have distinct identifiers
        spec1 = self.mod.entry_identifier("foo bar", 1, "debug")
        spec2 = self.mod.entry_identifier("foo+bar", 1, "debug")
        self.assertNotEqual(spec1, spec2)
        self.assertNotEqual(id1, spec1)
        self.assertIn("-s-", spec1)

    def test_collect_entries_unique_identifiers_for_base_and_specialisations(
        self,
    ) -> None:
        """Verify collected entries have unique identifiers across multiple profiles and specialisations."""
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        kernel = self.temp_dir / "kernel"
        kernel.touch()
        initrd = self.temp_dir / "initrd"
        initrd.touch()

        bootspec = self.mod.BootSpec(
            init=Path("/nix/store/init"),
            initrd=initrd,
            initrd_secrets=None,
            extra_initrds=(),
            kernel=kernel,
            kernel_params=(),
            label="Test",
            toplevel=toplevel,
            specialisations={
                "debug": self.mod.BootSpec(
                    init=Path("/nix/store/init-debug"),
                    initrd=initrd,
                    initrd_secrets=None,
                    extra_initrds=(),
                    kernel=kernel,
                    kernel_params=(),
                    label="Test (debug)",
                    toplevel=self.temp_dir / "toplevel-debug",
                    specialisations={},
                    devicetree=None,
                )
            },
            devicetree=None,
        )

        def mock_get_generations(profile: str | None = None) -> list[Any]:
            return [self.mod.SystemIdentifier(profile, 1)]

        with patch.object(
            self.mod, "get_generations", side_effect=mock_get_generations
        ), patch.object(
            self.mod, "get_profiles", return_value=["foo bar", "foo+bar"]
        ), patch.object(
            self.mod, "load_bootspec", return_value=bootspec
        ):
            entries = self.mod.collect_entries(current_toplevel=toplevel)

        # 3 profiles (None, 'foo bar', 'foo+bar') * 2 entries each (base + specialisation) = 6
        self.assertEqual(len(entries), 6)
        identifiers = [e.identifier for e in entries]
        self.assertEqual(len(identifiers), len(set(identifiers)))
        self.assertIn("nixos-g1", identifiers)

    def test_duplicate_identifier_rejected_before_esp_mutation(self) -> None:
        """Verify that duplicate entry identifiers are rejected before any ESP mutations occur."""
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        kernel = self.temp_dir / "kernel"
        kernel.touch()

        dummy_entry1 = self.mod.BootEntry(
            identifier="duplicate-id",
            title="Entry 1",
            sort_key="00000000000000000001",
            kernel=Path("EFI/Sprout/nixos/k1.efi"),
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=Path("EFI/Sprout/nixos/k1.efi"),
                    source=kernel,
                    initrd_secrets=None,
                    generation=1,
                    critical=True,
                ),
            ),
            critical=True,
        )
        dummy_entry2 = self.mod.BootEntry(
            identifier="duplicate-id",
            title="Entry 2",
            sort_key="00000000000000000002",
            kernel=Path("EFI/Sprout/nixos/k2.efi"),
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=Path("EFI/Sprout/nixos/k2.efi"),
                    source=kernel,
                    initrd_secrets=None,
                    generation=2,
                    critical=False,
                ),
            ),
            critical=False,
        )

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[dummy_entry1, dummy_entry2]
        ):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.install_bootloader(toplevel)
            self.assertIn("duplicate boot entry identifier 'duplicate-id'", str(ctx.exception))

        # Assert no ESP mutations occurred
        self.assertFalse((self.esp_dir / self.mod.SPROUT_DIR).exists())
        self.assertFalse((self.esp_dir / self.mod.SPROUT_CONFIG).exists())

    def test_source_open_failure_non_critical_historical_artifact_omitted_and_valid_published(
        self,
    ) -> None:
        """Verify source read failure for non-critical historical artifact omits older entry while publishing valid critical entry."""
        toplevel_crit = self.temp_dir / "toplevel-crit"
        toplevel_crit.mkdir(parents=True, exist_ok=True)
        toplevel_older = self.temp_dir / "toplevel-older"
        toplevel_older.mkdir(parents=True, exist_ok=True)

        k_crit = self.temp_dir / "kernel-crit.efi"
        k_crit.write_text("k-crit")
        i_crit = self.temp_dir / "initrd-crit.img"
        i_crit.write_text("i-crit")

        k_older = self.temp_dir / "kernel-older.efi"
        k_older.write_text("k-older")
        i_older = self.temp_dir / "initrd-older.img"
        i_older.write_text("i-older")

        dest_k_crit = self.mod.artifact_path("kernel", k_crit)
        dest_i_crit = self.mod.artifact_path("initrd", i_crit)
        dest_k_older = self.mod.artifact_path("kernel", k_older)
        dest_i_older = self.mod.artifact_path("initrd", i_older)

        entry_crit = self.mod.BootEntry(
            identifier="nixos-g2",
            title="NixOS Gen 2",
            sort_key="g2",
            kernel=dest_k_crit,
            initrds=(dest_i_crit,),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k_crit,
                    source=k_crit,
                    initrd_secrets=None,
                    generation=2,
                    critical=True,
                ),
                self.mod.BootArtifact(
                    destination=dest_i_crit,
                    source=i_crit,
                    initrd_secrets=None,
                    generation=2,
                    critical=True,
                ),
            ),
            critical=True,
        )

        entry_older = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS Gen 1",
            sort_key="g1",
            kernel=dest_k_older,
            initrds=(dest_i_older,),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k_older,
                    source=k_older,
                    initrd_secrets=None,
                    generation=1,
                    critical=False,
                ),
                self.mod.BootArtifact(
                    destination=dest_i_older,
                    source=i_older,
                    initrd_secrets=None,
                    generation=1,
                    critical=False,
                ),
            ),
            critical=False,
        )

        orig_open = Path.open

        def mock_open(path_obj: Path, *args: Any, **kwargs: Any) -> Any:
            if path_obj.resolve() == k_older.resolve():
                raise OSError("Simulated source read failure on historical kernel")
            return orig_open(path_obj, *args, **kwargs)

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry_crit, entry_older]
        ), patch.object(Path, "open", mock_open):
            self.mod.install_bootloader(toplevel_crit)

        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        self.assertTrue(config_path.exists())
        config_text = config_path.read_text()

        # Gen 2 is present and default
        self.assertIn('[entries."nixos-g2"]', config_text)
        self.assertIn('default-entry = "nixos-g2"', config_text)

        # Gen 1 was omitted due to source artifact failure
        self.assertNotIn("nixos-g1", config_text)

        # Gen 2 artifacts installed
        self.assertTrue((self.esp_dir / dest_k_crit).exists())
        self.assertTrue((self.esp_dir / dest_i_crit).exists())

        # Gen 1 kernel was NOT installed
        self.assertFalse((self.esp_dir / dest_k_older).exists())

        # No temporary files remain
        self.assertEqual(list(self.esp_dir.rglob("*.tmp")), [])

    def test_source_open_failure_critical_artifact_aborts_and_preserves_config(
        self,
    ) -> None:
        """Verify source read failure for critical artifact aborts and leaves sprout.toml unchanged."""
        toplevel_crit = self.temp_dir / "toplevel-crit"
        toplevel_crit.mkdir(parents=True, exist_ok=True)

        k_crit = self.temp_dir / "kernel-crit.efi"
        k_crit.write_text("k-crit")
        dest_k_crit = self.mod.artifact_path("kernel", k_crit)

        entry_crit = self.mod.BootEntry(
            identifier="nixos-g2",
            title="NixOS Gen 2",
            sort_key="g2",
            kernel=dest_k_crit,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k_crit,
                    source=k_crit,
                    initrd_secrets=None,
                    generation=2,
                    critical=True,
                ),
            ),
            critical=True,
        )

        # Initial successful installation
        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry_crit]
        ):
            self.mod.install_bootloader(toplevel_crit)

        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        self.assertTrue(config_path.exists())
        original_config = config_path.read_text()

        # Now simulate a new critical kernel that fails to open on source side
        k_crit_new = self.temp_dir / "kernel-crit-new.efi"
        k_crit_new.write_text("k-crit-new")
        dest_k_crit_new = self.mod.artifact_path("kernel", k_crit_new)

        entry_crit_new = self.mod.BootEntry(
            identifier="nixos-g3",
            title="NixOS Gen 3",
            sort_key="g3",
            kernel=dest_k_crit_new,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k_crit_new,
                    source=k_crit_new,
                    initrd_secrets=None,
                    generation=3,
                    critical=True,
                ),
            ),
            critical=True,
        )

        orig_open = Path.open

        def mock_open(path_obj: Path, *args: Any, **kwargs: Any) -> Any:
            if path_obj.resolve() == k_crit_new.resolve():
                raise OSError("Simulated source read failure on critical kernel")
            return orig_open(path_obj, *args, **kwargs)

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry_crit_new]
        ), patch.object(Path, "open", mock_open):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.install_bootloader(toplevel_crit)
            self.assertIn("failed to read boot artifact source", str(ctx.exception))

        # Existing sprout.toml remains byte-for-byte unchanged
        self.assertEqual(config_path.read_text(), original_config)
        self.assertFalse((self.esp_dir / dest_k_crit_new).exists())
        self.assertEqual(list(self.esp_dir.rglob("*.tmp")), [])

    def test_esp_write_failure_during_non_critical_artifact_copy_aborts_installation(
        self,
    ) -> None:
        """Verify ESP-side write failure during non-critical artifact copy aborts rather than pruning entry."""
        toplevel_crit = self.temp_dir / "toplevel-crit"
        toplevel_crit.mkdir(parents=True, exist_ok=True)

        k_crit = self.temp_dir / "kernel-crit.efi"
        k_crit.write_text("k-crit")
        dest_k_crit = self.mod.artifact_path("kernel", k_crit)

        k_older = self.temp_dir / "kernel-older.efi"
        k_older.write_text("k-older")
        dest_k_older = self.mod.artifact_path("kernel", k_older)

        entry_crit = self.mod.BootEntry(
            identifier="nixos-g2",
            title="NixOS Gen 2",
            sort_key="g2",
            kernel=dest_k_crit,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k_crit,
                    source=k_crit,
                    initrd_secrets=None,
                    generation=2,
                    critical=True,
                ),
            ),
            critical=True,
        )

        entry_older = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS Gen 1",
            sort_key="g1",
            kernel=dest_k_older,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k_older,
                    source=k_older,
                    initrd_secrets=None,
                    generation=1,
                    critical=False,
                ),
            ),
            critical=False,
        )

        # Set an existing sprout.toml
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)
        initial_config = "version = 1\n# previous published config"
        config_path.write_text(initial_config)

        orig_replace = os.replace

        def mock_replace(src: Any, dst: Any) -> None:
            if Path(dst) == (self.esp_dir / dest_k_older):
                raise OSError(errno.EIO, "Simulated ESP filesystem write/replace failure")
            orig_replace(src, dst)

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry_crit, entry_older]
        ), patch("os.replace", mock_replace):
            with self.assertRaises(OSError) as ctx:
                self.mod.install_bootloader(toplevel_crit)
            self.assertEqual(ctx.exception.errno, errno.EIO)

        # Installation aborted: sprout.toml was NOT updated to a reduced menu
        self.assertEqual(config_path.read_text(), initial_config)
        # Temporary files cleaned up
        self.assertEqual(list(self.esp_dir.rglob("*.tmp")), [])

    def test_shared_artifact_with_critical_entry_remains_critical_on_failure(
        self,
    ) -> None:
        """Verify shared artifact referenced by both critical and older entries is treated as critical."""
        toplevel_crit = self.temp_dir / "toplevel-crit"
        toplevel_crit.mkdir(parents=True, exist_ok=True)

        k_shared = self.temp_dir / "kernel-shared.efi"
        k_shared.write_text("k-shared")
        dest_k_shared = self.mod.artifact_path("kernel", k_shared)

        entry_older = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS Gen 1",
            sort_key="g1",
            kernel=dest_k_shared,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k_shared,
                    source=k_shared,
                    initrd_secrets=None,
                    generation=1,
                    critical=False,
                ),
            ),
            critical=False,
        )

        entry_crit = self.mod.BootEntry(
            identifier="nixos-g2",
            title="NixOS Gen 2",
            sort_key="g2",
            kernel=dest_k_shared,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k_shared,
                    source=k_shared,
                    initrd_secrets=None,
                    generation=2,
                    critical=True,
                ),
            ),
            critical=True,
        )

        orig_open = Path.open

        def mock_open(path_obj: Path, *args: Any, **kwargs: Any) -> Any:
            if path_obj.resolve() == k_shared.resolve():
                raise OSError("Simulated read failure on shared kernel")
            return orig_open(path_obj, *args, **kwargs)

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry_older, entry_crit]
        ), patch.object(Path, "open", mock_open):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.install_bootloader(toplevel_crit)
            self.assertIn("failed to read boot artifact source", str(ctx.exception))

    def test_failed_copies_clean_up_temporary_files_and_never_publish_partially_written_dest(
        self,
    ) -> None:
        """Verify failed copies clean up temporary files and never publish partially written destination."""
        k_src = self.temp_dir / "kernel-large.efi"
        k_src.write_bytes(b"A" * 131072)  # 128 KiB
        dest_k = self.esp_dir / self.mod.NIXOS_DIR / "kernel-test.efi"

        # Case A: Source read failure midway through copy
        class FailingReader:
            def __init__(self, real_file: Any) -> None:
                self.real_file = real_file
                self.calls = 0

            def read(self, size: int = -1) -> bytes:
                self.calls += 1
                if self.calls > 1:
                    raise OSError("Simulated I/O failure on source read chunk")
                return self.real_file.read(size)  # type: ignore[no-any-return]

            def close(self) -> None:
                self.real_file.close()

        orig_open = Path.open

        def mock_open(path_obj: Path, *args: Any, **kwargs: Any) -> Any:
            if path_obj.resolve() == k_src.resolve():
                f = orig_open(path_obj, *args, **kwargs)
                return FailingReader(f)
            return orig_open(path_obj, *args, **kwargs)

        with patch.object(Path, "open", mock_open):
            with self.assertRaises(self.mod.SourceArtifactError):
                self.mod.atomic_copy(k_src, dest_k, replace=True)

        self.assertFalse(dest_k.exists(), "Destination must not exist after source failure")
        self.assertEqual(list(self.esp_dir.rglob("*.tmp")), [], "No temp files on ESP")

        # Case B: Destination fsync failure
        with patch("os.fsync", side_effect=OSError("Simulated ESP fsync error")):
            with self.assertRaises(OSError):
                self.mod.atomic_copy(k_src, dest_k, replace=True)

        self.assertFalse(dest_k.exists(), "Destination must not exist after destination failure")
        self.assertEqual(list(self.esp_dir.rglob("*.tmp")), [], "No temp files on ESP")

    def test_fallback_installation_failure_restores_loaders_and_config(
        self,
    ) -> None:
        """Verify fallback installation failure after primary loader replacement restores loaders and config."""
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        kernel = self.temp_dir / "kernel.efi"
        kernel.write_text("kernel-bytes")
        dest_k = self.mod.artifact_path("kernel", kernel)
        entry = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS 1",
            sort_key="00000000000000000001",
            kernel=dest_k,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k,
                    source=kernel,
                    initrd_secrets=None,
                    generation=1,
                    critical=True,
                ),
            ),
            critical=True,
        )

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            removable=True,
        )
        fallback_path = self.esp_dir / "EFI" / "BOOT" / mod.removable_loader_name()
        primary_path = self.esp_dir / mod.SPROUT_BINARY
        config_path = self.esp_dir / mod.SPROUT_CONFIG

        # Set up prior installed loader, fallback loader, and configuration
        primary_path.parent.mkdir(parents=True, exist_ok=True)
        primary_path.write_text("old-primary-loader")
        fallback_path.parent.mkdir(parents=True, exist_ok=True)
        fallback_path.write_text("old-fallback-loader")
        config_path.write_text("version = 1\n# previous published config")

        # New binary content
        self.sprout_source.write_text("new-primary-loader")

        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ), patch.object(
            mod,
            "install_removable_loader",
            side_effect=RuntimeError("simulated fallback installation failure"),
        ):
            with self.assertRaises(RuntimeError) as ctx:
                mod.install_bootloader(toplevel)
            self.assertIn("simulated fallback installation failure", str(ctx.exception))

        # Both loaders and configuration retain their exact previous contents
        self.assertEqual(primary_path.read_text(), "old-primary-loader")
        self.assertEqual(fallback_path.read_text(), "old-fallback-loader")
        self.assertEqual(
            config_path.read_text(), "version = 1\n# previous published config"
        )
        self.assertEqual(list(self.esp_dir.rglob("*.tmp")), [])

    def test_config_publication_failure_restores_loaders_and_config_without_gc(
        self,
    ) -> None:
        """Verify failure during configuration publication restores loaders and skips garbage collection."""
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        kernel = self.temp_dir / "kernel.efi"
        kernel.write_text("kernel-bytes")
        dest_k = self.mod.artifact_path("kernel", kernel)
        entry = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS 1",
            sort_key="00000000000000000001",
            kernel=dest_k,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k,
                    source=kernel,
                    initrd_secrets=None,
                    generation=1,
                    critical=True,
                ),
            ),
            critical=True,
        )

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            removable=True,
        )
        fallback_path = self.esp_dir / "EFI" / "BOOT" / mod.removable_loader_name()
        primary_path = self.esp_dir / mod.SPROUT_BINARY
        config_path = self.esp_dir / mod.SPROUT_CONFIG

        primary_path.parent.mkdir(parents=True, exist_ok=True)
        primary_path.write_text("old-primary-loader")
        fallback_path.parent.mkdir(parents=True, exist_ok=True)
        fallback_path.write_text("old-fallback-loader")
        config_path.write_text("version = 1\n# previous published config")

        # Obsolete file to verify garbage collection does NOT run
        obsolete_driver = self.esp_dir / mod.DRIVERS_DIR / "obsolete.efi"
        obsolete_driver.parent.mkdir(parents=True, exist_ok=True)
        obsolete_driver.write_text("obsolete-driver-content")

        self.sprout_source.write_text("new-primary-loader")

        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ), patch.object(
            mod,
            "atomic_write_text",
            side_effect=OSError(errno.EIO, "simulated disk error during config publication"),
        ):
            with self.assertRaises(OSError) as ctx:
                mod.install_bootloader(toplevel)
            self.assertEqual(ctx.exception.errno, errno.EIO)

        # Primary loader, fallback loader, and configuration are restored
        self.assertEqual(primary_path.read_text(), "old-primary-loader")
        self.assertEqual(fallback_path.read_text(), "old-fallback-loader")
        self.assertEqual(
            config_path.read_text(), "version = 1\n# previous published config"
        )

        # Garbage collection did NOT run
        self.assertTrue(obsolete_driver.exists())
        self.assertEqual(obsolete_driver.read_text(), "obsolete-driver-content")
        self.assertEqual(list(self.esp_dir.rglob("*.tmp")), [])

    def test_loader_rollback_previously_absent_loader_paths(self) -> None:
        """Verify pre-publication failure removes newly created loader paths and preserves pre-existing fallback."""
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        kernel = self.temp_dir / "kernel.efi"
        kernel.write_text("kernel-bytes")
        dest_k = self.mod.artifact_path("kernel", kernel)
        entry = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS 1",
            sort_key="00000000000000000001",
            kernel=dest_k,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k,
                    source=kernel,
                    initrd_secrets=None,
                    generation=1,
                    critical=True,
                ),
            ),
            critical=True,
        )

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            removable=True,
        )
        fallback_path = self.esp_dir / "EFI" / "BOOT" / mod.removable_loader_name()
        primary_path = self.esp_dir / mod.SPROUT_BINARY
        config_path = self.esp_dir / mod.SPROUT_CONFIG

        # Fresh installation: primary loader and sprout.toml do NOT exist.
        # Pre-existing fallback from another bootloader (e.g. GRUB) exists.
        fallback_path.parent.mkdir(parents=True, exist_ok=True)
        fallback_path.write_text("foreign-grub-fallback-binary")

        self.assertFalse(primary_path.exists())
        self.assertFalse(config_path.exists())

        self.sprout_source.write_text("new-primary-loader")

        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ), patch.object(
            mod,
            "atomic_write_text",
            side_effect=RuntimeError("simulated config write failure"),
        ):
            with self.assertRaises(RuntimeError) as ctx:
                mod.install_bootloader(toplevel)
            self.assertIn("simulated config write failure", str(ctx.exception))

        # Newly created primary loader path was unlinked on rollback
        self.assertFalse(primary_path.exists())

        # Pre-existing fallback loader is preserved with original contents
        self.assertTrue(fallback_path.exists())
        self.assertEqual(fallback_path.read_text(), "foreign-grub-fallback-binary")

        # sprout.toml was never published
        self.assertFalse(config_path.exists())
        self.assertEqual(list(self.esp_dir.rglob("*.tmp")), [])

    def test_nvram_failure_after_publication_preserves_published_files_and_skips_gc(
        self,
    ) -> None:
        """Verify NVRAM failure after publication does not roll back loaders/config and skips garbage collection."""
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        kernel = self.temp_dir / "kernel.efi"
        kernel.write_text("kernel-bytes")
        dest_k = self.mod.artifact_path("kernel", kernel)
        entry = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS 1",
            sort_key="00000000000000000001",
            kernel=dest_k,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k,
                    source=kernel,
                    initrd_secrets=None,
                    generation=1,
                    critical=True,
                ),
            ),
            critical=True,
        )

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            removable=True,
            can_touch_efi=True,
        )
        fallback_path = self.esp_dir / "EFI" / "BOOT" / mod.removable_loader_name()
        primary_path = self.esp_dir / mod.SPROUT_BINARY
        config_path = self.esp_dir / mod.SPROUT_CONFIG

        primary_path.parent.mkdir(parents=True, exist_ok=True)
        primary_path.write_text("old-primary-loader")
        fallback_path.parent.mkdir(parents=True, exist_ok=True)
        fallback_path.write_text("old-fallback-loader")
        config_path.write_text("version = 1\n# previous published config")

        obsolete_driver = self.esp_dir / mod.DRIVERS_DIR / "obsolete.efi"
        obsolete_driver.parent.mkdir(parents=True, exist_ok=True)
        obsolete_driver.write_text("obsolete-driver-content")

        self.sprout_source.write_text("new-primary-loader")

        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ), patch.object(
            mod, "check_efivars"
        ), patch.object(
            mod, "capture", return_value=""
        ), patch.object(
            mod,
            "install_nvram_entry",
            side_effect=RuntimeError("simulated efibootmgr error"),
        ):
            with self.assertRaises(RuntimeError) as ctx:
                mod.install_bootloader(toplevel)
            self.assertIn("simulated efibootmgr error", str(ctx.exception))

        # Publication committed: loaders and configuration remain updated
        self.assertEqual(primary_path.read_text(), "new-primary-loader")
        self.assertEqual(fallback_path.read_text(), "new-primary-loader")
        self.assertIn("nixos-g1", config_path.read_text())
        self.assertNotIn("previous published config", config_path.read_text())

        # Garbage collection was NOT run
        self.assertTrue(obsolete_driver.exists())

    def test_successful_retry_after_nvram_failure(self) -> None:
        """Verify successful retry after NVRAM failure converges to expected state and runs garbage collection."""
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        kernel = self.temp_dir / "kernel.efi"
        kernel.write_text("kernel-bytes")
        dest_k = self.mod.artifact_path("kernel", kernel)
        entry = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS 1",
            sort_key="00000000000000000001",
            kernel=dest_k,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k,
                    source=kernel,
                    initrd_secrets=None,
                    generation=1,
                    critical=True,
                ),
            ),
            critical=True,
        )

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            removable=True,
            can_touch_efi=True,
        )
        fallback_path = self.esp_dir / "EFI" / "BOOT" / mod.removable_loader_name()
        primary_path = self.esp_dir / mod.SPROUT_BINARY
        config_path = self.esp_dir / mod.SPROUT_CONFIG

        primary_path.parent.mkdir(parents=True, exist_ok=True)
        primary_path.write_text("old-primary-loader")
        fallback_path.parent.mkdir(parents=True, exist_ok=True)
        fallback_path.write_text("old-fallback-loader")
        config_path.write_text("version = 1\n# previous published config")

        obsolete_driver = self.esp_dir / mod.DRIVERS_DIR / "obsolete.efi"
        obsolete_driver.parent.mkdir(parents=True, exist_ok=True)
        obsolete_driver.write_text("obsolete-driver-content")

        self.sprout_source.write_text("new-primary-loader")

        # First run: NVRAM fails
        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ), patch.object(
            mod, "check_efivars"
        ), patch.object(
            mod, "capture", return_value=""
        ), patch.object(
            mod,
            "install_nvram_entry",
            side_effect=RuntimeError("simulated efibootmgr error"),
        ):
            with self.assertRaises(RuntimeError):
                mod.install_bootloader(toplevel)

        # Files remain published, obsolete driver not yet collected
        self.assertEqual(primary_path.read_text(), "new-primary-loader")
        self.assertEqual(fallback_path.read_text(), "new-primary-loader")
        self.assertTrue(obsolete_driver.exists())

        # Second run: Retry succeeds
        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ), patch.object(
            mod, "check_efivars"
        ), patch.object(
            mod, "capture", return_value=""
        ), patch.object(mod, "install_nvram_entry", return_value=None):
            mod.install_bootloader(toplevel)

        # Loaders and configuration are published, and garbage collection ran
        self.assertEqual(primary_path.read_text(), "new-primary-loader")
        self.assertEqual(fallback_path.read_text(), "new-primary-loader")
        self.assertIn("nixos-g1", config_path.read_text())
        self.assertFalse(
            obsolete_driver.exists(), "Obsolete driver collected on successful retry"
        )
        self.assertEqual(list(self.esp_dir.rglob("*.tmp")), [])

    def test_normal_successful_installation_removable_enabled_and_disabled(
        self,
    ) -> None:
        """Confirm normal successful installation works with removable mode enabled and disabled."""
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        kernel = self.temp_dir / "kernel.efi"
        kernel.write_text("kernel-bytes")
        dest_k = self.mod.artifact_path("kernel", kernel)
        entry = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS 1",
            sort_key="00000000000000000001",
            kernel=dest_k,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k,
                    source=kernel,
                    initrd_secrets=None,
                    generation=1,
                    critical=True,
                ),
            ),
            critical=True,
        )

        # Case A: Removable disabled
        esp_disabled = self.temp_dir / "esp-disabled"
        esp_disabled.mkdir(parents=True, exist_ok=True)
        mod_disabled = load_sprout_installer(
            esp_disabled,
            sprout_binary=self.sprout_source,
            removable=False,
        )
        with patch.object(mod_disabled, "check_mountpoint"), patch.object(
            mod_disabled, "collect_entries", return_value=[entry]
        ):
            mod_disabled.install_bootloader(toplevel)

        self.assertTrue((esp_disabled / mod_disabled.SPROUT_BINARY).exists())
        self.assertTrue((esp_disabled / mod_disabled.SPROUT_CONFIG).exists())
        fallback_path_disabled = (
            esp_disabled / "EFI" / "BOOT" / mod_disabled.removable_loader_name()
        )
        self.assertFalse(fallback_path_disabled.exists())

        # Case B: Removable enabled
        esp_enabled = self.temp_dir / "esp-enabled"
        esp_enabled.mkdir(parents=True, exist_ok=True)
        mod_enabled = load_sprout_installer(
            esp_enabled,
            sprout_binary=self.sprout_source,
            removable=True,
        )
        with patch.object(mod_enabled, "check_mountpoint"), patch.object(
            mod_enabled, "collect_entries", return_value=[entry]
        ):
            mod_enabled.install_bootloader(toplevel)

        self.assertTrue((esp_enabled / mod_enabled.SPROUT_BINARY).exists())
        self.assertTrue((esp_enabled / mod_enabled.SPROUT_CONFIG).exists())
        fallback_path_enabled = (
            esp_enabled / "EFI" / "BOOT" / mod_enabled.removable_loader_name()
        )
        self.assertTrue(fallback_path_enabled.exists())
        self.assertEqual(
            fallback_path_enabled.read_bytes(),
            (esp_enabled / mod_enabled.SPROUT_BINARY).read_bytes(),
        )

    def test_restoration_failure_reports_clearly_and_chains_exception(
        self,
    ) -> None:
        """Verify failure during rollback reports clearly to stderr and chains from original exception."""
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        kernel = self.temp_dir / "kernel.efi"
        kernel.write_text("kernel-bytes")
        dest_k = self.mod.artifact_path("kernel", kernel)
        entry = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS 1",
            sort_key="00000000000000000001",
            kernel=dest_k,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k,
                    source=kernel,
                    initrd_secrets=None,
                    generation=1,
                    critical=True,
                ),
            ),
            critical=True,
        )

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            removable=False,
        )
        primary_path = self.esp_dir / mod.SPROUT_BINARY
        primary_path.parent.mkdir(parents=True, exist_ok=True)
        primary_path.write_text("prior-loader")

        # Inject restoration error in rollback
        orig_atomic_copy = mod.atomic_copy

        def failing_restore_copy(src: Path, dst: Path, **kwargs: Any) -> Any:
            if dst == primary_path and "loader_0.efi" in src.name:
                raise OSError(errno.EROFS, "Simulated read-only ESP during restoration")
            return orig_atomic_copy(src, dst, **kwargs)

        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ), patch.object(
            mod,
            "atomic_write_text",
            side_effect=RuntimeError("injected pre-publication error"),
        ), patch.object(mod, "atomic_copy", failing_restore_copy):
            with self.assertRaises(RuntimeError) as ctx:
                mod.install_bootloader(toplevel)

            # Clearly reports restoration failure
            self.assertIn("failed to restore bootloader files", str(ctx.exception))
            # Chained from original pre-publication error
            self.assertIsNotNone(ctx.exception.__cause__)
            assert ctx.exception.__cause__ is not None
            self.assertIn(
                "injected pre-publication error", str(ctx.exception.__cause__)
            )

    def test_post_replacement_directory_close_error_does_not_rollback_loaders(
        self,
    ) -> None:
        """Verify directory close error in fsync_path after os.replace does not trigger unsafe loader rollback."""
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        kernel = self.temp_dir / "kernel.efi"
        kernel.write_text("kernel-bytes")
        dest_k = self.mod.artifact_path("kernel", kernel)
        entry = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS 1",
            sort_key="00000000000000000001",
            kernel=dest_k,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k,
                    source=kernel,
                    initrd_secrets=None,
                    generation=1,
                    critical=True,
                ),
            ),
            critical=True,
        )

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            removable=True,
        )
        fallback_path = self.esp_dir / "EFI" / "BOOT" / mod.removable_loader_name()
        primary_path = self.esp_dir / mod.SPROUT_BINARY
        config_path = self.esp_dir / mod.SPROUT_CONFIG

        primary_path.parent.mkdir(parents=True, exist_ok=True)
        primary_path.write_text("old-primary-loader")
        fallback_path.parent.mkdir(parents=True, exist_ok=True)
        fallback_path.write_text("old-fallback-loader")
        config_path.write_text("version = 1\n# previous published config")

        self.sprout_source.write_text("new-primary-loader")

        orig_close = os.close
        close_error_injected = False

        def mock_close(fd: int) -> None:
            nonlocal close_error_injected
            if (
                not close_error_injected
                and config_path.exists()
                and "nixos-g1" in config_path.read_text()
            ):
                close_error_injected = True
                orig_close(fd)
                raise OSError(errno.EIO, "Simulated error closing directory after replace")
            orig_close(fd)

        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ), patch("os.close", mock_close):
            mod.install_bootloader(toplevel)

        # Close error occurred post-replacement
        self.assertTrue(close_error_injected, "Close error was injected during post-replacement")

        # Loaders and config remain on the newly published version
        self.assertEqual(primary_path.read_text(), "new-primary-loader")
        self.assertEqual(fallback_path.read_text(), "new-primary-loader")
        self.assertIn("nixos-g1", config_path.read_text())
        self.assertNotIn("previous published config", config_path.read_text())
        self.assertEqual(list(self.esp_dir.rglob("*.tmp")), [])

    def test_post_replacement_fsync_path_error_does_not_rollback_loaders(
        self,
    ) -> None:
        """Verify directory durability error after os.replace does not trigger unsafe loader rollback."""
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        kernel = self.temp_dir / "kernel.efi"
        kernel.write_text("kernel-bytes")
        dest_k = self.mod.artifact_path("kernel", kernel)
        entry = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS 1",
            sort_key="00000000000000000001",
            kernel=dest_k,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k,
                    source=kernel,
                    initrd_secrets=None,
                    generation=1,
                    critical=True,
                ),
            ),
            critical=True,
        )

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            removable=True,
        )
        fallback_path = self.esp_dir / "EFI" / "BOOT" / mod.removable_loader_name()
        primary_path = self.esp_dir / mod.SPROUT_BINARY
        config_path = self.esp_dir / mod.SPROUT_CONFIG

        primary_path.parent.mkdir(parents=True, exist_ok=True)
        primary_path.write_text("old-primary-loader")
        fallback_path.parent.mkdir(parents=True, exist_ok=True)
        fallback_path.write_text("old-fallback-loader")
        config_path.write_text("version = 1\n# previous published config")

        self.sprout_source.write_text("new-primary-loader")

        orig_fsync_path = mod.fsync_path
        fsync_error_injected = False

        def mock_fsync_path(path: Path) -> None:
            nonlocal fsync_error_injected
            if config_path.exists() and "nixos-g1" in config_path.read_text():
                fsync_error_injected = True
                raise OSError(errno.EIO, "Simulated directory durability failure")
            orig_fsync_path(path)

        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ), patch.object(mod, "fsync_path", mock_fsync_path):
            mod.install_bootloader(toplevel)

        # Durability error occurred post-replacement
        self.assertTrue(fsync_error_injected, "Durability error was injected during post-replacement")

        # Loaders and config remain on the newly published version
        self.assertEqual(primary_path.read_text(), "new-primary-loader")
        self.assertEqual(fallback_path.read_text(), "new-primary-loader")
        self.assertIn("nixos-g1", config_path.read_text())
        self.assertNotIn("previous published config", config_path.read_text())
        self.assertEqual(list(self.esp_dir.rglob("*.tmp")), [])

    def test_replace_failure_preserves_error_and_rolls_back_loaders(
        self,
    ) -> None:
        """Verify failure during os.replace on sprout.toml preserves error and rolls back loaders."""
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        kernel = self.temp_dir / "kernel.efi"
        kernel.write_text("kernel-bytes")
        dest_k = self.mod.artifact_path("kernel", kernel)
        entry = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS 1",
            sort_key="00000000000000000001",
            kernel=dest_k,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k,
                    source=kernel,
                    initrd_secrets=None,
                    generation=1,
                    critical=True,
                ),
            ),
            critical=True,
        )

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            removable=True,
        )
        fallback_path = self.esp_dir / "EFI" / "BOOT" / mod.removable_loader_name()
        primary_path = self.esp_dir / mod.SPROUT_BINARY
        config_path = self.esp_dir / mod.SPROUT_CONFIG

        primary_path.parent.mkdir(parents=True, exist_ok=True)
        primary_path.write_text("old-primary-loader")
        fallback_path.parent.mkdir(parents=True, exist_ok=True)
        fallback_path.write_text("old-fallback-loader")
        config_path.write_text("version = 1\n# previous published config")

        self.sprout_source.write_text("new-primary-loader")

        orig_replace = os.replace

        def mock_replace(src: Any, dst: Any) -> None:
            if Path(dst) == config_path:
                raise OSError(errno.ENOSPC, "No space left on device during replace")
            orig_replace(src, dst)

        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ), patch("os.replace", mock_replace):
            with self.assertRaises(OSError) as ctx:
                mod.install_bootloader(toplevel)
            self.assertEqual(ctx.exception.errno, errno.ENOSPC)

        # Pre-replacement failure rolled loaders back and preserved old config
        self.assertEqual(primary_path.read_text(), "old-primary-loader")
        self.assertEqual(fallback_path.read_text(), "old-fallback-loader")
        self.assertEqual(config_path.read_text(), "version = 1\n# previous published config")
        self.assertEqual(list(self.esp_dir.rglob("*.tmp")), [])


class BootSpecParserTest(unittest.TestCase):
    def setUp(self) -> None:
        self.mod = load_sprout_installer(Path("/dummy/esp"))

    def test_bootspec_from_json_minimal_required_data(self) -> None:
        """Verify parsing minimal BootSpec document containing only required v1 data."""
        doc = {
            "org.nixos.bootspec.v1": {
                "system": "x86_64-linux",
                "kernel": "/nix/store/def-kernel/bzImage",
                "kernelParams": ["console=ttyS0"],
                "label": "NixOS 24.11 (Linux 6.6.20)",
                "init": "/nix/store/abc-init",
                "toplevel": "/nix/store/xyz-toplevel",
            }
        }
        spec = self.mod.bootspec_from_json(doc)
        self.assertEqual(spec.init, Path("/nix/store/abc-init"))
        self.assertEqual(spec.toplevel, Path("/nix/store/xyz-toplevel"))
        self.assertEqual(spec.label, "NixOS 24.11 (Linux 6.6.20)")
        self.assertEqual(spec.kernel, Path("/nix/store/def-kernel/bzImage"))
        self.assertIsNone(spec.initrd)
        self.assertIsNone(spec.initrd_secrets)
        self.assertEqual(spec.extra_initrds, ())
        self.assertEqual(spec.kernel_params, ("console=ttyS0",))
        self.assertEqual(spec.specialisations, {})
        self.assertIsNone(spec.devicetree)

    def test_bootspec_from_json_all_optional_and_extension_fields(self) -> None:
        """Verify parsing BootSpec with all optional fields, extra-initrds, devicetree, and specialisations."""
        doc = {
            "org.nixos.bootspec.v1": {
                "system": "x86_64-linux",
                "init": "/nix/store/abc-init",
                "toplevel": "/nix/store/xyz-toplevel",
                "label": "NixOS 24.11 (Linux 6.6.20)",
                "kernel": "/nix/store/def-kernel/bzImage",
                "initrd": "/nix/store/ghi-initrd/initrd",
                "initrdSecrets": "/nix/store/jkl-secrets/append-secrets.sh",
                "kernelParams": ["console=ttyS0", "loglevel=4"],
            },
            "org.nixos.extra-initrd.v1": {
                "paths": ["extra1.img", "extra2.img"],
            },
            "org.nixos.systemd-boot": {
                "devicetree": "/nix/store/mno-dtb/bcm2711.dtb",
            },
            "org.nixos.specialisation.v1": {
                "fallback": {
                    "org.nixos.bootspec.v1": {
                        "system": "x86_64-linux",
                        "init": "/nix/store/abc-init",
                        "toplevel": "/nix/store/special-toplevel",
                        "label": "NixOS 24.11 (Fallback)",
                        "kernel": "/nix/store/spec-kernel/bzImage",
                        "initrd": "/nix/store/spec-initrd/initrd",
                        "kernelParams": ["nomodeset"],
                    }
                }
            },
        }
        spec = self.mod.bootspec_from_json(doc)
        self.assertEqual(spec.init, Path("/nix/store/abc-init"))
        self.assertEqual(spec.toplevel, Path("/nix/store/xyz-toplevel"))
        self.assertEqual(spec.label, "NixOS 24.11 (Linux 6.6.20)")
        self.assertEqual(spec.kernel, Path("/nix/store/def-kernel/bzImage"))
        self.assertEqual(spec.initrd, Path("/nix/store/ghi-initrd/initrd"))
        self.assertEqual(
            spec.initrd_secrets, Path("/nix/store/jkl-secrets/append-secrets.sh")
        )
        self.assertEqual(
            spec.extra_initrds, (Path("extra1.img"), Path("extra2.img"))
        )
        self.assertEqual(spec.kernel_params, ("console=ttyS0", "loglevel=4"))
        self.assertEqual(spec.devicetree, Path("/nix/store/mno-dtb/bcm2711.dtb"))

        # Verify specialisation parsed correctly
        self.assertIn("fallback", spec.specialisations)
        sub = spec.specialisations["fallback"]
        self.assertEqual(sub.init, Path("/nix/store/abc-init"))
        self.assertEqual(sub.toplevel, Path("/nix/store/special-toplevel"))
        self.assertEqual(sub.label, "NixOS 24.11 (Fallback)")
        self.assertEqual(sub.kernel, Path("/nix/store/spec-kernel/bzImage"))
        self.assertEqual(sub.initrd, Path("/nix/store/spec-initrd/initrd"))
        self.assertEqual(sub.kernel_params, ("nomodeset",))
        self.assertEqual(sub.specialisations, {})
        self.assertIsNone(sub.devicetree)

    def test_bootspec_from_json_devicetree_absent_or_null(self) -> None:
        """Verify devicetree is None when absent, missing field, null, or noncanonical alias."""
        base: dict[str, Any] = {
            "org.nixos.bootspec.v1": {
                "system": "x86_64-linux",
                "kernel": "/nix/store/kernel/bzImage",
                "kernelParams": ["console=ttyS0"],
                "label": "NixOS 24.11",
                "init": "/nix/store/init",
                "toplevel": "/nix/store/toplevel",
            }
        }
        # Absent extension
        self.assertIsNone(self.mod.bootspec_from_json(base).devicetree)

        # Extension present with missing devicetree
        doc_empty_ext = {**base, "org.nixos.systemd-boot": {}}
        self.assertIsNone(self.mod.bootspec_from_json(doc_empty_ext).devicetree)

        # Extension present with null devicetree
        doc_null_dt = {**base, "org.nixos.systemd-boot": {"devicetree": None}}
        self.assertIsNone(self.mod.bootspec_from_json(doc_null_dt).devicetree)

        # Unknown extension keys must not be reinterpreted as fields of another extension
        doc_unknown_alias = {
            **base,
            "org.nixos.systemd-boot.devicetree": "/nix/store/dot.dtb",
        }
        self.assertIsNone(
            self.mod.bootspec_from_json(doc_unknown_alias).devicetree
        )

    def test_bootspec_from_json_validation_errors(self) -> None:
        """Verify invalid document structure and field types raise RuntimeError."""
        # Missing org.nixos.bootspec.v1
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.bootspec_from_json({})
        self.assertIn(
            'does not contain "org.nixos.bootspec.v1"', str(ctx.exception)
        )

        # Missing init
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.bootspec_from_json(
                {"org.nixos.bootspec.v1": {"toplevel": "/toplevel"}}
            )
        self.assertIn(
            'does not contain "org.nixos.bootspec.v1.init"', str(ctx.exception)
        )

        # Missing toplevel
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.bootspec_from_json(
                {"org.nixos.bootspec.v1": {"init": "/init"}}
            )
        self.assertIn(
            'does not contain "org.nixos.bootspec.v1.toplevel"',
            str(ctx.exception),
        )

        base: dict[str, Any] = {
            "org.nixos.bootspec.v1": {
                "system": "x86_64-linux",
                "kernel": "/nix/store/kernel/bzImage",
                "kernelParams": ["console=ttyS0"],
                "label": "NixOS 24.11",
                "init": "/nix/store/init",
                "toplevel": "/nix/store/toplevel",
            }
        }

        # kernelParams not a list
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.bootspec_from_json(
                {
                    "org.nixos.bootspec.v1": {
                        **base["org.nixos.bootspec.v1"],
                        "kernelParams": "bad",
                    }
                }
            )
        self.assertIn('"kernelParams" is not an array', str(ctx.exception))

        # extra-initrd not a dict
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.bootspec_from_json(
                {**base, "org.nixos.extra-initrd.v1": "bad"}
            )
        self.assertIn(
            'invalid "org.nixos.extra-initrd.v1" extension', str(ctx.exception)
        )

        # extra-initrd.paths not a list
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.bootspec_from_json(
                {**base, "org.nixos.extra-initrd.v1": {"paths": "bad"}}
            )
        self.assertIn(
            '"org.nixos.extra-initrd.v1.paths" is not an array',
            str(ctx.exception),
        )

        # specialisation not a dict
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.bootspec_from_json(
                {**base, "org.nixos.specialisation.v1": "bad"}
            )
        self.assertIn(
            'invalid "org.nixos.specialisation.v1" extension', str(ctx.exception)
        )

        # systemd-boot not a dict (string)
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.bootspec_from_json(
                {**base, "org.nixos.systemd-boot": "bad"}
            )
        self.assertIn(
            'invalid "org.nixos.systemd-boot" extension', str(ctx.exception)
        )

        # systemd-boot not a dict (null / None)
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.bootspec_from_json(
                {**base, "org.nixos.systemd-boot": None}
            )
        self.assertIn(
            'invalid "org.nixos.systemd-boot" extension', str(ctx.exception)
        )

        # devicetree not a string
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.bootspec_from_json(
                {**base, "org.nixos.systemd-boot": {"devicetree": 123}}
            )
        self.assertIn(
            '"org.nixos.systemd-boot.devicetree" is not a string',
            str(ctx.exception),
        )


class NvramEntryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir_obj = tempfile.TemporaryDirectory()
        self.esp_dir = Path(self.temp_dir_obj.name).resolve()
        self.mod = load_sprout_installer(
            self.esp_dir,
            entry_label="NixOS Sprout",
        )

    def tearDown(self) -> None:
        self.temp_dir_obj.cleanup()

    def test_exact_label_and_exact_loader_path_recognized_as_already_installed(
        self,
    ) -> None:
        """Verify exact label and exact loader path are recognized as installed without creating new entry."""
        efibootmgr_output = (
            "BootCurrent: 0001\n"
            "Timeout: 5 seconds\n"
            "BootOrder: 0001,0002\n"
            "Boot0001* NixOS Sprout\tHD(1,GPT,e9a4f4d2-36c9-4b6a-939e-473d091a1348,0x800,0x100000)/File(\\EFI\\Sprout\\sprout.efi)\n"
            "Boot0002  UEFI OS\tHD(1,GPT,e9a4f4d2-36c9-4b6a-939e-473d091a1348,0x800,0x100000)/File(\\EFI\\BOOT\\BOOTX64.EFI)\n"
        )
        with patch.object(self.mod, "check_efivars"), patch.object(
            self.mod, "capture", return_value=efibootmgr_output
        ), patch.object(self.mod, "get_esp_device") as mock_get_esp, patch.object(
            self.mod, "run"
        ) as mock_run:
            self.mod.install_nvram_entry()
            mock_run.assert_not_called()
            mock_get_esp.assert_not_called()

    def test_direct_hd_path_without_file_wrapper_recognized_as_matching_entry(
        self,
    ) -> None:
        """Verify efibootmgr -v output with direct HD(...)/\\path format is recognized without re-installing."""
        efibootmgr_output = (
            "BootCurrent: 0001\n"
            "Timeout: 5 seconds\n"
            "BootOrder: 0003,0001\n"
            "Boot0003* NixOS Sprout\tHD(1,GPT,d85a1112-70b9-450f-a496-e137887532a2,0x800,0x100000)/\\EFI\\Sprout\\sprout.efi\n"
        )
        with patch.object(self.mod, "check_efivars"), patch.object(
            self.mod, "capture", return_value=efibootmgr_output
        ), patch.object(self.mod, "get_esp_device") as mock_get_esp, patch.object(
            self.mod, "run"
        ) as mock_run:
            self.mod.install_nvram_entry()
            mock_run.assert_not_called()
            mock_get_esp.assert_not_called()

    def test_direct_hd_backslash_path_without_file_wrapper_recognized_as_matching_entry(
        self,
    ) -> None:
        """Verify efibootmgr -v output with direct HD(...)\\path format is recognized without re-installing."""
        efibootmgr_output = (
            "BootCurrent: 0001\n"
            "Timeout: 5 seconds\n"
            "BootOrder: 0003,0001\n"
            "Boot0003* NixOS Sprout\tHD(1,GPT,d85a1112-70b9-450f-a496-e137887532a2,0x800,0x100000)\\EFI\\Sprout\\sprout.efi\n"
        )
        with patch.object(self.mod, "check_efivars"), patch.object(
            self.mod, "capture", return_value=efibootmgr_output
        ), patch.object(self.mod, "get_esp_device") as mock_get_esp, patch.object(
            self.mod, "run"
        ) as mock_run:
            self.mod.install_nvram_entry()
            mock_run.assert_not_called()
            mock_get_esp.assert_not_called()

    def test_case_insensitive_matching_for_label_and_path(self) -> None:
        """Verify case-insensitive matching recognizes mixed-case label and loader path."""
        efibootmgr_output = (
            "Boot0001* nixos sprout\tHD(1,GPT,11111111-2222-3333-4444-555555555555,0x800,0x100000)/File(\\efi\\SPROUT\\SPROUT.EFI)\n"
        )
        with patch.object(self.mod, "check_efivars"), patch.object(
            self.mod, "capture", return_value=efibootmgr_output
        ), patch.object(self.mod, "run") as mock_run:
            self.mod.install_nvram_entry()
            mock_run.assert_not_called()

    def test_exact_label_different_path_fails_closed(self) -> None:
        """Verify exact label pointing to a different path fails closed without modifying or creating entries."""
        efibootmgr_output = (
            "Boot0001* NixOS Sprout\tHD(1,GPT,e9a4f4d2-36c9-4b6a-939e-473d091a1348,0x800,0x100000)/File(\\EFI\\systemd\\systemd-bootx64.efi)\n"
        )
        with patch.object(self.mod, "check_efivars"), patch.object(
            self.mod, "capture", return_value=efibootmgr_output
        ), patch.object(self.mod, "run") as mock_run:
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.install_nvram_entry()
            self.assertIn(
                "an existing UEFI entry named 'NixOS Sprout' does not point to \\EFI\\Sprout\\sprout.efi",
                str(ctx.exception),
            )
            mock_run.assert_not_called()

    def test_similar_labels_do_not_match(self) -> None:
        """Verify labels with prefixes or suffixes do not match and trigger new entry creation."""
        efibootmgr_output = (
            "Boot0001* NixOS Sprout Test\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Sprout\\sprout.efi)\n"
            "Boot0002* My NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Sprout\\sprout.efi)\n"
            "Boot0003* NixOS\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Sprout\\sprout.efi)\n"
            "Boot0004* Sprout\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Sprout\\sprout.efi)\n"
        )
        with patch.object(self.mod, "check_efivars"), patch.object(
            self.mod, "capture", return_value=efibootmgr_output
        ), patch.object(
            self.mod, "get_esp_device", return_value=("/dev/sda", "1")
        ), patch.object(
            self.mod, "run"
        ) as mock_run:
            self.mod.install_nvram_entry()
            mock_run.assert_called_once_with(
                [
                    self.mod.EFIBOOTMGR,
                    "-c",
                    "-d",
                    "/dev/sda",
                    "-p",
                    "1",
                    "-L",
                    "NixOS Sprout",
                    "-l",
                    r"\EFI\Sprout\sprout.efi",
                ]
            )

    def test_path_with_suffix_such_as_dot_old_rejected(self) -> None:
        """Verify paths merely containing expected loader path (e.g. .old suffix) are rejected."""
        efibootmgr_output = (
            "Boot0001* NixOS Sprout\tHD(1,GPT,e9a4f4d2-36c9-4b6a-939e-473d091a1348,0x800,0x100000)/File(\\EFI\\Sprout\\sprout.efi.old)\n"
        )
        with patch.object(self.mod, "check_efivars"), patch.object(
            self.mod, "capture", return_value=efibootmgr_output
        ), patch.object(self.mod, "run") as mock_run:
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.install_nvram_entry()
            self.assertIn(
                "an existing UEFI entry named 'NixOS Sprout' does not point to \\EFI\\Sprout\\sprout.efi",
                str(ctx.exception),
            )
            mock_run.assert_not_called()

    def test_no_matching_entry_invokes_efibootmgr_create(self) -> None:
        """Verify absent matching entry causes efibootmgr -c invocation with disk, partition, label, and loader."""
        efibootmgr_output = (
            "BootCurrent: 0002\n"
            "Timeout: 5 seconds\n"
            "BootOrder: 0000,0002\n"
            "Boot0000* Windows Boot Manager\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)\n"
            "Boot0002  UEFI OS\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\BOOT\\BOOTX64.EFI)\n"
        )
        with patch.object(self.mod, "check_efivars"), patch.object(
            self.mod, "capture", return_value=efibootmgr_output
        ), patch.object(
            self.mod, "get_esp_device", return_value=("/dev/nvme0n1", "2")
        ), patch.object(
            self.mod, "run"
        ) as mock_run:
            self.mod.install_nvram_entry()
            mock_run.assert_called_once_with(
                [
                    self.mod.EFIBOOTMGR,
                    "-c",
                    "-d",
                    "/dev/nvme0n1",
                    "-p",
                    "2",
                    "-L",
                    "NixOS Sprout",
                    "-l",
                    r"\EFI\Sprout\sprout.efi",
                ]
            )

    def test_retry_after_command_failure_detects_existing_entry_without_duplicates(
        self,
    ) -> None:
        """Verify command failure after firmware creates entry can be retried without duplicate creation."""
        initial_output = (
            "Boot0000* Windows Boot Manager\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)\n"
        )
        subsequent_output = (
            "Boot0000* Windows Boot Manager\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)\n"
            "Boot0001* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Sprout\\sprout.efi)\n"
        )

        with patch.object(self.mod, "check_efivars"), patch.object(
            self.mod, "capture", side_effect=[initial_output, subsequent_output]
        ), patch.object(
            self.mod, "get_esp_device", return_value=("/dev/nvme0n1", "1")
        ), patch.object(
            self.mod, "run", side_effect=subprocess.CalledProcessError(1, ["efibootmgr", "-c"])
        ) as mock_run:
            # First attempt fails after efibootmgr invocation
            with self.assertRaises(subprocess.CalledProcessError):
                self.mod.install_nvram_entry()
            mock_run.assert_called_once()

            # Second attempt (retry) discovers the entry created by firmware and does not create duplicate
            mock_run.reset_mock()
            self.mod.install_nvram_entry()
            mock_run.assert_not_called()

    def test_inspection_accepts_matching_entry(self) -> None:
        """Verify inspection accepts an entry matching label and loader path."""
        efibootmgr_output = (
            "Boot0001* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Sprout\\sprout.efi)\n"
        )
        with patch.object(self.mod, "check_efivars"), patch.object(
            self.mod, "capture", return_value=efibootmgr_output
        ), patch.object(self.mod, "run") as mock_run:
            status = self.mod.inspect_nvram_entry(raise_on_conflict=False)
            self.assertEqual(status, self.mod.NvramStatus.MATCHING)
            self.assertEqual(self.mod.inspect_nvram_entry(), self.mod.NvramStatus.MATCHING)
            self.mod.preflight_nvram()
            mock_run.assert_not_called()

    def test_inspection_reports_absent_when_no_matching_label(self) -> None:
        """Verify inspection reports absent without performing any firmware mutation when label is not present."""
        efibootmgr_output = (
            "Boot0000* Windows Boot Manager\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)\n"
            "Boot0002  UEFI OS\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\BOOT\\BOOTX64.EFI)\n"
        )
        with patch.object(self.mod, "check_efivars"), patch.object(
            self.mod, "capture", return_value=efibootmgr_output
        ), patch.object(self.mod, "run") as mock_run:
            status = self.mod.inspect_nvram_entry(raise_on_conflict=False)
            self.assertEqual(status, self.mod.NvramStatus.ABSENT)
            self.assertEqual(self.mod.inspect_nvram_entry(), self.mod.NvramStatus.ABSENT)
            self.mod.preflight_nvram()
            mock_run.assert_not_called()

    def test_inspection_rejects_same_label_different_path(self) -> None:
        """Verify inspection rejects same-label entry pointing to a different path."""
        efibootmgr_output = (
            "Boot0001* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\systemd\\systemd-bootx64.efi)\n"
        )
        with patch.object(self.mod, "check_efivars"), patch.object(
            self.mod, "capture", return_value=efibootmgr_output
        ), patch.object(self.mod, "run") as mock_run:
            status = self.mod.inspect_nvram_entry(raise_on_conflict=False)
            self.assertEqual(status, self.mod.NvramStatus.CONFLICT)

            with self.assertRaises(RuntimeError) as ctx:
                self.mod.inspect_nvram_entry()
            self.assertIn(
                "an existing UEFI entry named 'NixOS Sprout' does not point to \\EFI\\Sprout\\sprout.efi",
                str(ctx.exception),
            )

            with self.assertRaises(RuntimeError) as ctx_preflight:
                self.mod.preflight_nvram()
            self.assertIn(
                "an existing UEFI entry named 'NixOS Sprout' does not point to \\EFI\\Sprout\\sprout.efi",
                str(ctx_preflight.exception),
            )
            mock_run.assert_not_called()

    def test_inspection_rejects_same_label_unparseable_path(self) -> None:
        """Verify inspection rejects same-label entry whose loader path cannot be parsed."""
        efibootmgr_output = (
            "Boot0001* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/VenHw(1234)\n"
        )
        with patch.object(self.mod, "check_efivars"), patch.object(
            self.mod, "capture", return_value=efibootmgr_output
        ), patch.object(self.mod, "run") as mock_run:
            status = self.mod.inspect_nvram_entry(raise_on_conflict=False)
            self.assertEqual(status, self.mod.NvramStatus.CONFLICT)

            with self.assertRaises(RuntimeError) as ctx:
                self.mod.preflight_nvram()
            self.assertIn(
                "an existing UEFI entry named 'NixOS Sprout' does not point to \\EFI\\Sprout\\sprout.efi",
                str(ctx.exception),
            )
            mock_run.assert_not_called()

    def test_inspection_accepts_multiple_same_label_matching_entries(self) -> None:
        """Verify inspection accepts when multiple same-label entries all point to the expected loader."""
        efibootmgr_output = (
            "Boot0001* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Sprout\\sprout.efi)\n"
            "Boot0002* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/\\EFI\\Sprout\\sprout.efi\n"
            "Boot0003* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)\\EFI\\Sprout\\sprout.efi\n"
        )
        with patch.object(self.mod, "check_efivars"), patch.object(
            self.mod, "capture", return_value=efibootmgr_output
        ), patch.object(self.mod, "run") as mock_run:
            self.assertEqual(
                self.mod.inspect_nvram_entry(raise_on_conflict=False),
                self.mod.NvramStatus.MATCHING,
            )
            self.assertEqual(
                self.mod.inspect_nvram_entry(),
                self.mod.NvramStatus.MATCHING,
            )
            self.mod.preflight_nvram()
            mock_run.assert_not_called()

    def test_inspection_rejects_mixture_of_matching_and_conflicting_entries_regardless_of_order(
        self,
    ) -> None:
        """Verify inspection reports conflict when matching and conflicting/unparseable entries are mixed in any order."""
        variants = [
            # Matching first, conflicting path second
            (
                "Boot0001* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Sprout\\sprout.efi)\n"
                "Boot0002* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\other\\loader.efi)\n"
            ),
            # Conflicting path first, matching second
            (
                "Boot0001* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\other\\loader.efi)\n"
                "Boot0002* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Sprout\\sprout.efi)\n"
            ),
            # Matching first, unparseable second
            (
                "Boot0001* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Sprout\\sprout.efi)\n"
                "Boot0002* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Sprout\\sprout.efi)\n"
                "Boot0003* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)\\VenHw(1234)\n"
            ),
            # Unparseable first, matching second
            (
                "Boot0001* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/VenHw(1234)\n"
                "Boot0002* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Sprout\\sprout.efi)\n"
            ),
        ]
        for output in variants:
            with patch.object(self.mod, "check_efivars"), patch.object(
                self.mod, "capture", return_value=output
            ), patch.object(self.mod, "run") as mock_run:
                self.assertEqual(
                    self.mod.inspect_nvram_entry(raise_on_conflict=False),
                    self.mod.NvramStatus.CONFLICT,
                )
                with self.assertRaises(RuntimeError) as ctx:
                    self.mod.preflight_nvram()
                self.assertIn(
                    "an existing UEFI entry named 'NixOS Sprout' does not point to \\EFI\\Sprout\\sprout.efi",
                    str(ctx.exception),
                )
                mock_run.assert_not_called()

    def test_parse_nvram_entry_variants(self) -> None:
        """Verify parse_nvram_entry handles spaces, tabs, trailing data, and non-boot lines."""
        # Non-boot lines
        self.assertIsNone(self.mod.parse_nvram_entry("BootCurrent: 0001"))
        self.assertIsNone(self.mod.parse_nvram_entry("Timeout: 5 seconds"))
        self.assertIsNone(self.mod.parse_nvram_entry("BootOrder: 0001,0002"))

        # Space separated device path
        e1 = self.mod.parse_nvram_entry(
            "Boot0001* NixOS Sprout HD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Sprout\\sprout.efi)"
        )
        self.assertIsNotNone(e1)
        assert e1 is not None
        self.assertEqual(e1.label, "NixOS Sprout")
        self.assertEqual(e1.loader_path, r"\EFI\Sprout\sprout.efi")

        # Inactive entry (double space)
        e2 = self.mod.parse_nvram_entry(
            "Boot0002  UEFI OS\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\BOOT\\BOOTX64.EFI)"
        )
        self.assertIsNotNone(e2)
        assert e2 is not None
        self.assertEqual(e2.label, "UEFI OS")
        self.assertEqual(e2.loader_path, r"\EFI\BOOT\BOOTX64.EFI")

        # Trailing optional data
        e3 = self.mod.parse_nvram_entry(
            "Boot0000* Windows Boot Manager\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)WINDOWS........."
        )
        self.assertIsNotNone(e3)
        assert e3 is not None
        self.assertEqual(e3.label, "Windows Boot Manager")
        self.assertEqual(e3.loader_path, r"\EFI\Microsoft\Boot\bootmgfw.efi")

        # Non-file device path (e.g. BBS)
        e4 = self.mod.parse_nvram_entry("Boot0003* CD-ROM Drive\tBBS(CDROM,,0x0)")
        self.assertIsNotNone(e4)
        assert e4 is not None
        self.assertEqual(e4.label, "CD-ROM Drive")
        self.assertIsNone(e4.loader_path)

        # Direct EFI path following HD(...) without File(...) (slash-separated)
        e5 = self.mod.parse_nvram_entry(
            "Boot0003* NixOS Sprout\tHD(1,GPT,d85a1112-70b9-450f-a496-e137887532a2,0x800,0x100000)/\\EFI\\Sprout\\sprout.efi"
        )
        self.assertIsNotNone(e5)
        assert e5 is not None
        self.assertEqual(e5.label, "NixOS Sprout")
        self.assertEqual(e5.loader_path, r"\EFI\Sprout\sprout.efi")

        # Direct EFI path following HD(...) without File(...) (backslash-separated)
        e6 = self.mod.parse_nvram_entry(
            "Boot0003* NixOS Sprout\tHD(1,GPT,d85a1112-70b9-450f-a496-e137887532a2,0x800,0x100000)\\EFI\\Sprout\\sprout.efi"
        )
        self.assertIsNotNone(e6)
        assert e6 is not None
        self.assertEqual(e6.label, "NixOS Sprout")
        self.assertEqual(e6.loader_path, r"\EFI\Sprout\sprout.efi")

        # Non-file device path following HD(...) (slash-separated)
        e7 = self.mod.parse_nvram_entry(
            "Boot0004* Hard Drive\tHD(1,GPT,1234,0x800,0x100000)/VenHw(1234)"
        )
        self.assertIsNotNone(e7)
        assert e7 is not None
        self.assertEqual(e7.label, "Hard Drive")
        self.assertIsNone(e7.loader_path)

        # Non-file device path following HD(...) (slash-separated with backslash)
        e8 = self.mod.parse_nvram_entry(
            "Boot0004* Hard Drive\tHD(1,GPT,1234,0x800,0x100000)/\\VenHw(1234)"
        )
        self.assertIsNotNone(e8)
        assert e8 is not None
        self.assertEqual(e8.label, "Hard Drive")
        self.assertIsNone(e8.loader_path)

        # Non-file device path following HD(...) (backslash-separated)
        e9 = self.mod.parse_nvram_entry(
            "Boot0004* Hard Drive\tHD(1,GPT,1234,0x800,0x100000)\\VenHw(1234)"
        )
        self.assertIsNotNone(e9)
        assert e9 is not None
        self.assertEqual(e9.label, "Hard Drive")
        self.assertIsNone(e9.loader_path)


class NvramPreflightIntegrationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir_obj = tempfile.TemporaryDirectory()
        self.temp_dir = Path(self.temp_dir_obj.name).resolve()
        self.esp_dir = self.temp_dir / "esp"
        self.esp_dir.mkdir(parents=True, exist_ok=True)
        self.sprout_source = self.temp_dir / "sprout-src.efi"
        self.sprout_source.write_text("dummy-sprout-binary")

    def tearDown(self) -> None:
        self.temp_dir_obj.cleanup()

    def _create_entry(self, mod: Any, identifier: str, gen: int) -> Any:
        kernel = self.temp_dir / f"k{gen}.efi"
        kernel.write_text(f"kernel-{gen}")
        initrd = self.temp_dir / f"i{gen}.img"
        initrd.write_text(f"initrd-{gen}")

        dest_k = mod.artifact_path("kernel", kernel)
        dest_i = mod.artifact_path("initrd", initrd)

        return mod.BootEntry(
            identifier=identifier,
            title=f"Generation {gen}",
            sort_key=f"{gen:020d}",
            kernel=dest_k,
            initrds=(dest_i,),
            options=("init=/init",),
            artifacts=(
                mod.BootArtifact(
                    destination=dest_k,
                    source=kernel,
                    initrd_secrets=None,
                    generation=gen,
                    critical=True,
                ),
                mod.BootArtifact(
                    destination=dest_i,
                    source=initrd,
                    initrd_secrets=None,
                    generation=gen,
                    critical=True,
                ),
            ),
            critical=True,
        )

    def test_preflight_conflict_aborts_before_any_esp_mutation(self) -> None:
        """Verify preflight conflict with CAN_TOUCH_EFI_VARIABLES aborts before any directory creation or ESP file write."""
        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            can_touch_efi=True,
        )
        pre_existing = self.esp_dir / "pre_existing.txt"
        pre_existing.write_text("keep-this-unmodified")

        entry = self._create_entry(mod, "nixos-g1", 1)
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)

        conflicting_output = (
            "Boot0001* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\other\\loader.efi)\n"
        )

        mock_gc = Mock()
        mock_run = Mock()

        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ), patch.object(
            mod, "check_efivars"
        ), patch.object(
            mod, "capture", return_value=conflicting_output
        ), patch.object(
            mod, "run", mock_run
        ), patch.object(
            mod, "garbage_collect", mock_gc
        ):
            with self.assertRaises(RuntimeError) as ctx:
                mod.install_bootloader(toplevel)
            self.assertIn(
                "an existing UEFI entry named 'NixOS Sprout' does not point to \\EFI\\Sprout\\sprout.efi",
                str(ctx.exception),
            )

        # Pre-existing file is untouched
        self.assertEqual(pre_existing.read_text(), "keep-this-unmodified")

        # No Sprout directories or files were created
        self.assertFalse((self.esp_dir / "EFI").exists())
        self.assertFalse((self.esp_dir / "sprout.toml").exists())

        # No NVRAM mutations or garbage collection occurred
        mock_run.assert_not_called()
        mock_gc.assert_not_called()

    def test_preflight_efivars_unavailable_aborts_before_esp_mutation(self) -> None:
        """Verify failure to inspect EFI variables during preflight aborts before creating ESP directories or files."""
        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            can_touch_efi=True,
        )
        entry = self._create_entry(mod, "nixos-g1", 1)
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)

        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ), patch.object(
            mod,
            "check_efivars",
            side_effect=RuntimeError("EFI variables are unavailable at /sys/firmware/efi/efivars"),
        ):
            with self.assertRaises(RuntimeError) as ctx:
                mod.install_bootloader(toplevel)
            self.assertIn("EFI variables are unavailable", str(ctx.exception))

        self.assertFalse((self.esp_dir / "EFI").exists())
        self.assertFalse((self.esp_dir / "sprout.toml").exists())

    def test_preflight_skipped_when_can_touch_efi_disabled(self) -> None:
        """Verify preflight is skipped when CAN_TOUCH_EFI_VARIABLES is false and removable loader installs normally."""
        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            can_touch_efi=False,
            removable=True,
        )
        entry = self._create_entry(mod, "nixos-g1", 1)
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)

        mock_check_efivars = Mock()
        mock_capture = Mock()

        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ), patch.object(
            mod, "check_efivars", mock_check_efivars
        ), patch.object(
            mod, "capture", mock_capture
        ):
            mod.install_bootloader(toplevel)

        # Preflight must NOT have run efivars or capture
        mock_check_efivars.assert_not_called()
        mock_capture.assert_not_called()

        # Removable loader and config are installed
        removable_path = self.esp_dir / "EFI" / "BOOT" / mod.removable_loader_name()
        self.assertTrue(removable_path.exists())
        self.assertTrue((self.esp_dir / mod.SPROUT_CONFIG).exists())

    def test_nvram_reinspection_at_actual_install_stage_catches_new_conflict(self) -> None:
        """Verify installer re-inspects NVRAM at install stage and aborts without creating entry if state changed."""
        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            can_touch_efi=True,
        )
        entry = self._create_entry(mod, "nixos-g1", 1)
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)

        obsolete_driver = self.esp_dir / mod.DRIVERS_DIR / "obsolete.efi"
        obsolete_driver.parent.mkdir(parents=True, exist_ok=True)
        obsolete_driver.write_text("obsolete-content")

        preflight_output = "Boot0000* Windows Boot Manager\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)\n"
        install_output = (
            "Boot0000* Windows Boot Manager\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)\n"
            "Boot0001* NixOS Sprout\tHD(1,GPT,1234,0x800,0x100000)/File(\\EFI\\other\\loader.efi)\n"
        )

        mock_run = Mock()

        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ), patch.object(
            mod, "check_efivars"
        ), patch.object(
            mod, "capture", side_effect=[preflight_output, install_output]
        ), patch.object(
            mod, "run", mock_run
        ):
            with self.assertRaises(RuntimeError) as ctx:
                mod.install_bootloader(toplevel)
            self.assertIn(
                "an existing UEFI entry named 'NixOS Sprout' does not point to \\EFI\\Sprout\\sprout.efi",
                str(ctx.exception),
            )

        # Fresh inspection detected conflict and aborted: efibootmgr -c must NOT be called
        mock_run.assert_not_called()

        # Files already published remain intact
        config_path = self.esp_dir / mod.SPROUT_CONFIG
        self.assertTrue(config_path.exists())
        self.assertIn("nixos-g1", config_path.read_text())

        # Garbage collection was skipped due to error
        self.assertTrue(obsolete_driver.exists())


class EspMountpointAndDeviceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir_obj = tempfile.TemporaryDirectory()
        self.esp_dir = Path(self.temp_dir_obj.name).resolve()
        self.mod = load_sprout_installer(
            self.esp_dir,
            entry_label="NixOS Sprout",
        )

    def tearDown(self) -> None:
        self.temp_dir_obj.cleanup()

    def test_exact_vfat_mountpoint_accepted(self) -> None:
        """Verify an exact VFAT mountpoint is accepted without error."""
        captured_commands: list[list[str]] = []

        def mock_capture(cmd: Any) -> str:
            cmd_strs = [str(x) for x in cmd]
            captured_commands.append(cmd_strs)
            if cmd_strs[0] == self.mod.FINDMNT:
                self.assertIn("--mountpoint", cmd_strs)
                self.assertNotIn("--target", cmd_strs)
                if "--output" in cmd_strs and "SOURCE" in cmd_strs:
                    return "/dev/nvme0n1p1"
                if "--output" in cmd_strs and "FSTYPE" in cmd_strs:
                    return "vfat"
            raise AssertionError(f"Unexpected command: {cmd_strs}")

        with patch.object(self.mod, "capture", side_effect=mock_capture):
            self.mod.check_mountpoint()

        self.assertEqual(len(captured_commands), 2)

    def test_exact_vfat_mountpoint_case_insensitive(self) -> None:
        """Verify VFAT filesystem type check is case-insensitive."""
        def mock_capture(cmd: Any) -> str:
            cmd_strs = [str(x) for x in cmd]
            if cmd_strs[0] == self.mod.FINDMNT:
                if "SOURCE" in cmd_strs:
                    return "/dev/sda1"
                if "FSTYPE" in cmd_strs:
                    return "VFAT"
            raise AssertionError(f"Unexpected command: {cmd_strs}")

        with patch.object(self.mod, "capture", side_effect=mock_capture):
            self.mod.check_mountpoint()

    def test_ordinary_directory_inside_vfat_mount_rejected(self) -> None:
        """Verify an ordinary directory inside a VFAT mount is rejected when not a mountpoint."""
        def mock_capture(cmd: Any) -> str:
            cmd_strs = [str(x) for x in cmd]
            if cmd_strs[0] == self.mod.FINDMNT:
                self.assertIn("--mountpoint", cmd_strs)
                self.assertNotIn("--target", cmd_strs)
                # findmnt exits with 1 when the specified path is not a mountpoint
                raise subprocess.CalledProcessError(1, cmd_strs)
            raise AssertionError(f"Unexpected command: {cmd_strs}")

        with patch.object(self.mod, "capture", side_effect=mock_capture):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.check_mountpoint()
            self.assertEqual(
                str(ctx.exception),
                f"{self.mod.EFI_SYS_MOUNT_POINT} is not a mounted filesystem",
            )

    def test_missing_mountpoint_rejected(self) -> None:
        """Verify a missing mountpoint where findmnt fails is rejected."""
        with patch.object(
            self.mod, "capture", side_effect=subprocess.CalledProcessError(1, ["findmnt"])
        ):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.check_mountpoint()
            self.assertEqual(
                str(ctx.exception),
                f"{self.mod.EFI_SYS_MOUNT_POINT} is not a mounted filesystem",
            )

    def test_empty_source_rejected(self) -> None:
        """Verify an empty mount source is rejected."""
        with patch.object(self.mod, "capture", return_value=""):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.check_mountpoint()
            self.assertEqual(
                str(ctx.exception),
                f"{self.mod.EFI_SYS_MOUNT_POINT} is not a mounted filesystem",
            )

    def test_non_vfat_filesystem_type_rejected(self) -> None:
        """Verify a filesystem type other than VFAT is rejected."""
        def mock_capture(cmd: Any) -> str:
            cmd_strs = [str(x) for x in cmd]
            if "SOURCE" in cmd_strs:
                return "/dev/sda1"
            if "FSTYPE" in cmd_strs:
                return "ext4"
            raise AssertionError(f"Unexpected command: {cmd_strs}")

        with patch.object(self.mod, "capture", side_effect=mock_capture):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.check_mountpoint()
            self.assertEqual(
                str(ctx.exception),
                f"{self.mod.EFI_SYS_MOUNT_POINT} is mounted as 'ext4'; "
                "Sprout currently requires a vfat ESP",
            )

    def test_install_bootloader_rejects_non_mountpoint_before_mutating_esp(self) -> None:
        """Verify install_bootloader aborts on invalid mountpoint before creating directories or modifying ESP."""
        def mock_capture(cmd: Any) -> str:
            cmd_strs = [str(x) for x in cmd]
            if cmd_strs[0] == self.mod.FINDMNT:
                raise subprocess.CalledProcessError(1, cmd_strs)
            raise AssertionError(f"Unexpected command: {cmd_strs}")

        with patch.object(self.mod, "capture", side_effect=mock_capture):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.install_bootloader(self.esp_dir)
            self.assertIn("is not a mounted filesystem", str(ctx.exception))

        # ESP was not mutated
        self.assertFalse((self.esp_dir / "EFI").exists())

    def test_device_discovery_uses_exact_mountpoint_and_returns_disk_and_partition(
        self,
    ) -> None:
        """Verify get_esp_device uses exact mountpoint lookup and returns disk and positive partition number."""
        captured_commands: list[list[str]] = []

        def mock_capture(cmd: Any) -> str:
            cmd_strs = [str(x) for x in cmd]
            captured_commands.append(cmd_strs)
            if cmd_strs[0] == self.mod.FINDMNT:
                self.assertIn("--mountpoint", cmd_strs)
                self.assertNotIn("--target", cmd_strs)
                return "/dev/nvme0n1p1"
            if cmd_strs[0] == self.mod.LSBLK:
                if "PKNAME" in cmd_strs:
                    return "nvme0n1"
                if "PARTN" in cmd_strs:
                    return "1"
            raise AssertionError(f"Unexpected command: {cmd_strs}")

        with patch.object(self.mod, "capture", side_effect=mock_capture):
            disk, partition = self.mod.get_esp_device()

        self.assertEqual(disk, "/dev/nvme0n1")
        self.assertEqual(partition, "1")
        self.assertEqual(len(captured_commands), 3)

    def test_device_discovery_rejects_non_mountpoint(self) -> None:
        """Verify get_esp_device rejects a path that is not an exact mountpoint."""
        def mock_capture(cmd: Any) -> str:
            cmd_strs = [str(x) for x in cmd]
            if cmd_strs[0] == self.mod.FINDMNT:
                self.assertIn("--mountpoint", cmd_strs)
                self.assertNotIn("--target", cmd_strs)
                raise subprocess.CalledProcessError(1, cmd_strs)
            raise AssertionError(f"Unexpected command: {cmd_strs}")

        with patch.object(self.mod, "capture", side_effect=mock_capture):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.get_esp_device()
            self.assertIn("is not a mounted filesystem", str(ctx.exception))

    def test_device_discovery_missing_parent_disk_fails_closed(self) -> None:
        """Verify missing parent disk information raises RuntimeError."""
        def mock_capture(cmd: Any) -> str:
            cmd_strs = [str(x) for x in cmd]
            if cmd_strs[0] == self.mod.FINDMNT:
                return "/dev/sda1"
            if cmd_strs[0] == self.mod.LSBLK:
                if "PKNAME" in cmd_strs:
                    return ""
                if "PARTN" in cmd_strs:
                    return "1"
            raise AssertionError(f"Unexpected command: {cmd_strs}")

        with patch.object(self.mod, "capture", side_effect=mock_capture):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.get_esp_device()
            self.assertEqual(
                str(ctx.exception),
                "could not determine the parent disk of ESP device /dev/sda1",
            )

    def test_device_discovery_lsblk_parent_error_fails_closed(self) -> None:
        """Verify lsblk failure for parent disk raises RuntimeError."""
        def mock_capture(cmd: Any) -> str:
            cmd_strs = [str(x) for x in cmd]
            if cmd_strs[0] == self.mod.FINDMNT:
                return "/dev/sda1"
            if cmd_strs[0] == self.mod.LSBLK and "PKNAME" in cmd_strs:
                raise subprocess.CalledProcessError(1, cmd_strs)
            raise AssertionError(f"Unexpected command: {cmd_strs}")

        with patch.object(self.mod, "capture", side_effect=mock_capture):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.get_esp_device()
            self.assertEqual(
                str(ctx.exception),
                "could not determine the parent disk of ESP device /dev/sda1",
            )

    def test_device_discovery_invalid_partition_number_fails_closed(self) -> None:
        """Verify invalid partition numbers (0, negative, non-digit, empty) fail closed."""
        for invalid_part in ["0", "-1", "abc", "", "   "]:
            with self.subTest(invalid_part=invalid_part):
                def mock_capture(cmd: Any, part: str = invalid_part) -> str:
                    cmd_strs = [str(x) for x in cmd]
                    if cmd_strs[0] == self.mod.FINDMNT:
                        return "/dev/sda1"
                    if cmd_strs[0] == self.mod.LSBLK:
                        if "PKNAME" in cmd_strs:
                            return "sda"
                        if "PARTN" in cmd_strs:
                            return part
                    raise AssertionError(f"Unexpected command: {cmd_strs}")

                with patch.object(self.mod, "capture", side_effect=mock_capture):
                    with self.assertRaises(RuntimeError) as ctx:
                        self.mod.get_esp_device()
                    self.assertEqual(
                        str(ctx.exception),
                        "could not determine the partition number of ESP device /dev/sda1",
                    )

    def test_device_discovery_lsblk_partition_error_fails_closed(self) -> None:
        """Verify lsblk failure for partition number raises RuntimeError."""
        def mock_capture(cmd: Any) -> str:
            cmd_strs = [str(x) for x in cmd]
            if cmd_strs[0] == self.mod.FINDMNT:
                return "/dev/sda1"
            if cmd_strs[0] == self.mod.LSBLK:
                if "PKNAME" in cmd_strs:
                    return "sda"
                if "PARTN" in cmd_strs:
                    raise subprocess.CalledProcessError(1, cmd_strs)
            raise AssertionError(f"Unexpected command: {cmd_strs}")

        with patch.object(self.mod, "capture", side_effect=mock_capture):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.get_esp_device()
            self.assertEqual(
                str(ctx.exception),
                "could not determine the partition number of ESP device /dev/sda1",
            )


class EspDurabilityAndSyncTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir_obj = tempfile.TemporaryDirectory()
        self.temp_dir = Path(self.temp_dir_obj.name).resolve()
        self.esp_dir = self.temp_dir / "esp"
        self.esp_dir.mkdir(parents=True, exist_ok=True)

        self.old_cwd = Path.cwd()
        os.chdir(self.temp_dir)

        self.sprout_source = self.temp_dir / "source-sprout.efi"
        self.sprout_source.write_text("sprout-bin")

        self.mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
        )

    def tearDown(self) -> None:
        os.chdir(self.old_cwd)
        self.temp_dir_obj.cleanup()

    def test_sync_filesystem_fails_when_path_cannot_be_opened(self) -> None:
        """Verify sync_filesystem raises OSError when the directory cannot be opened."""
        nonexistent = self.temp_dir / "nonexistent-dir"
        with self.assertRaises(OSError) as ctx:
            self.mod.sync_filesystem(nonexistent)
        self.assertEqual(ctx.exception.errno, errno.ENOENT)

        with patch("os.open", side_effect=OSError(errno.EACCES, "Permission denied")):
            with self.assertRaises(OSError) as ctx2:
                self.mod.sync_filesystem(self.esp_dir)
            self.assertEqual(ctx2.exception.errno, errno.EACCES)

    def test_sync_filesystem_fails_when_syncfs_reports_error_with_cleanup(self) -> None:
        """Verify sync_filesystem raises OSError on syncfs failure, cleans up fd, and handles unset errno."""
        fake_fd = 42
        mock_close = Mock()

        # Case A: syncfs fails with errno set (e.g. EIO)
        with patch("os.open", return_value=fake_fd), patch(
            "os.close", mock_close
        ), patch.object(self.mod.libc, "syncfs", return_value=-1), patch(
            "ctypes.get_errno", return_value=errno.EIO
        ):
            with self.assertRaises(OSError) as ctx:
                self.mod.sync_filesystem(self.esp_dir)

            self.assertEqual(ctx.exception.errno, errno.EIO)
            self.assertEqual(ctx.exception.filename, str(self.esp_dir))
            mock_close.assert_called_once_with(fake_fd)

        # Case B: syncfs fails with errno unset (errno == 0), avoiding misleading "Success" message
        mock_close.reset_mock()
        with patch("os.open", return_value=fake_fd), patch(
            "os.close", mock_close
        ), patch.object(self.mod.libc, "syncfs", return_value=-1), patch(
            "ctypes.get_errno", return_value=0
        ):
            with self.assertRaises(OSError) as ctx:
                self.mod.sync_filesystem(self.esp_dir)

            self.assertNotIn("Success", str(ctx.exception))
            self.assertIn("could not sync", str(ctx.exception))
            mock_close.assert_called_once_with(fake_fd)

        # Case C: os.close raises OSError during cleanup, preserving the syncfs error
        mock_close.reset_mock()
        mock_close.side_effect = OSError(errno.EBADF, "Bad file descriptor")
        with patch("os.open", return_value=fake_fd), patch(
            "os.close", mock_close
        ), patch.object(self.mod.libc, "syncfs", return_value=-1), patch(
            "ctypes.get_errno", return_value=errno.ENOSPC
        ):
            with self.assertRaises(OSError) as ctx:
                self.mod.sync_filesystem(self.esp_dir)

            self.assertEqual(ctx.exception.errno, errno.ENOSPC)
            mock_close.assert_called_once_with(fake_fd)

    def test_early_sync_failure_preserves_published_files_and_skips_nvram_and_gc(
        self,
    ) -> None:
        """Verify early ESP sync failure after publication does not roll back loaders/config and aborts NVRAM and GC."""
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)
        kernel = self.temp_dir / "kernel.efi"
        kernel.write_text("kernel-bytes")
        dest_k = self.mod.artifact_path("kernel", kernel)
        entry = self.mod.BootEntry(
            identifier="nixos-g1",
            title="NixOS 1",
            sort_key="00000000000000000001",
            kernel=dest_k,
            initrds=(),
            options=("init=/init",),
            artifacts=(
                self.mod.BootArtifact(
                    destination=dest_k,
                    source=kernel,
                    initrd_secrets=None,
                    generation=1,
                    critical=True,
                ),
            ),
            critical=True,
        )

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            removable=True,
            can_touch_efi=True,
        )
        fallback_path = self.esp_dir / "EFI" / "BOOT" / mod.removable_loader_name()
        primary_path = self.esp_dir / mod.SPROUT_BINARY
        config_path = self.esp_dir / mod.SPROUT_CONFIG

        primary_path.parent.mkdir(parents=True, exist_ok=True)
        primary_path.write_text("old-primary-loader")
        fallback_path.parent.mkdir(parents=True, exist_ok=True)
        fallback_path.write_text("old-fallback-loader")
        config_path.write_text("version = 1\n# previous published config")

        obsolete_driver = self.esp_dir / mod.DRIVERS_DIR / "obsolete.efi"
        obsolete_driver.parent.mkdir(parents=True, exist_ok=True)
        obsolete_driver.write_text("obsolete-driver-content")

        self.sprout_source.write_text("new-primary-loader")

        mock_nvram = Mock()
        mock_gc = Mock()

        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ), patch.object(
            mod, "check_efivars"
        ), patch.object(
            mod, "capture", return_value=""
        ), patch.object(
            mod,
            "sync_filesystem",
            side_effect=OSError(errno.EIO, "Simulated ESP sync failure at early checkpoint"),
        ), patch.object(
            mod, "install_nvram_entry", mock_nvram
        ), patch.object(
            mod, "garbage_collect", mock_gc
        ):
            with self.assertRaises(OSError) as ctx:
                mod.install_bootloader(toplevel)
            self.assertEqual(ctx.exception.errno, errno.EIO)
            self.assertIn("Simulated ESP sync failure at early checkpoint", str(ctx.exception))

        # Checkpoint failed: NVRAM and GC must NOT have run
        mock_nvram.assert_not_called()
        mock_gc.assert_not_called()

        # Publication already committed: loaders and configuration remain updated (no rollback)
        self.assertEqual(primary_path.read_text(), "new-primary-loader")
        self.assertEqual(fallback_path.read_text(), "new-primary-loader")
        self.assertIn("nixos-g1", config_path.read_text())

        # Old boot files preserved (obsolete driver was not garbage-collected)
        self.assertTrue(obsolete_driver.exists())
        self.assertEqual(obsolete_driver.read_text(), "obsolete-driver-content")

    def test_main_successful_install_failed_final_sync_exits_nonzero(self) -> None:
        """Verify successful installation with failed final sync reports error and exits nonzero."""
        toplevel = self.temp_dir / "toplevel"
        stderr_buffer = io.StringIO()

        with patch.object(
            self.mod, "install_bootloader", return_value=None
        ) as mock_install, patch.object(
            self.mod,
            "sync_filesystem",
            side_effect=OSError(errno.EIO, "Simulated final sync I/O error"),
        ), patch(
            "sys.stderr", stderr_buffer
        ):
            with self.assertRaises(SystemExit) as ctx:
                self.mod.main([str(toplevel)])

            self.assertEqual(ctx.exception.code, 1)
            mock_install.assert_called_once_with(Path(str(toplevel)))
            self.assertIn("Simulated final sync I/O error", stderr_buffer.getvalue())

    def test_main_installation_failure_preserved_when_final_sync_also_fails(self) -> None:
        """Verify earlier installation failure remains primary exit status and error when final sync fails."""
        toplevel = self.temp_dir / "toplevel"

        # Case A: CalledProcessError during installation
        cmd_error = subprocess.CalledProcessError(2, ["efibootmgr", "-c"])
        stderr_buffer = io.StringIO()

        with patch.object(
            self.mod, "install_bootloader", side_effect=cmd_error
        ), patch.object(
            self.mod,
            "sync_filesystem",
            side_effect=OSError(errno.EIO, "Simulated final sync I/O error"),
        ), patch(
            "sys.stderr", stderr_buffer
        ):
            with self.assertRaises(SystemExit) as ctx:
                self.mod.main([str(toplevel)])

            self.assertEqual(ctx.exception.code, 2)
            self.assertIs(ctx.exception.__cause__, cmd_error)
            output = stderr_buffer.getvalue()
            # Both primary installation error and synchronization failure are reported
            self.assertIn("error: command failed: efibootmgr -c", output)
            self.assertIn("Simulated final sync I/O error", output)

        # Case B: RuntimeError during installation
        runtime_error = RuntimeError("Simulated bootloader preparation failure")
        stderr_buffer_b = io.StringIO()

        with patch.object(
            self.mod, "install_bootloader", side_effect=runtime_error
        ), patch.object(
            self.mod,
            "sync_filesystem",
            side_effect=OSError(errno.EIO, "Simulated final sync I/O error"),
        ), patch(
            "sys.stderr", stderr_buffer_b
        ):
            with self.assertRaises(SystemExit) as ctx:
                self.mod.main([str(toplevel)])

            self.assertEqual(ctx.exception.code, 1)
            self.assertIs(ctx.exception.__cause__, runtime_error)
            output_b = stderr_buffer_b.getvalue()
            self.assertIn("error: Simulated bootloader preparation failure", output_b)
            self.assertIn("Simulated final sync I/O error", output_b)

        # Case C: Earlier installation failure with successful final sync preserves error and status
        stderr_buffer_c = io.StringIO()
        with patch.object(
            self.mod, "install_bootloader", side_effect=cmd_error
        ), patch.object(
            self.mod, "sync_filesystem", return_value=None
        ), patch(
            "sys.stderr", stderr_buffer_c
        ):
            with self.assertRaises(SystemExit) as ctx:
                self.mod.main([str(toplevel)])

            self.assertEqual(ctx.exception.code, 2)
            self.assertIs(ctx.exception.__cause__, cmd_error)
            output_c = stderr_buffer_c.getvalue()
            self.assertIn("error: command failed: efibootmgr -c", output_c)
            self.assertNotIn("Simulated final sync", output_c)

        # Case D: Completely successful installation and sync exits normally (exit 0)
        with patch.object(
            self.mod, "install_bootloader", return_value=None
        ), patch.object(
            self.mod, "sync_filesystem", return_value=None
        ):
            # Calling main([str(toplevel)]) returns normally without raising SystemExit
            self.mod.main([str(toplevel)])

    def test_main_unexpected_exception_triggers_final_sync_and_preserves_exception(
        self,
    ) -> None:
        """Verify an unexpected exception during installation triggers final sync and is propagated."""
        toplevel = self.temp_dir / "toplevel"
        mock_sync = Mock()

        with patch.object(
            self.mod,
            "install_bootloader",
            side_effect=ValueError("unexpected installation error"),
        ), patch.object(self.mod, "sync_filesystem", mock_sync):
            with self.assertRaises(ValueError) as ctx:
                self.mod.main([str(toplevel)])

            self.assertEqual(str(ctx.exception), "unexpected installation error")
            mock_sync.assert_called_once_with(self.mod.EFI_SYS_MOUNT_POINT)

    def test_main_unexpected_exception_with_final_sync_failure_propagates_original_and_reports_sync(
        self,
    ) -> None:
        """Verify unexpected exception is preserved and not masked when final sync also fails."""
        toplevel = self.temp_dir / "toplevel"
        stderr_buffer = io.StringIO()

        with patch.object(
            self.mod,
            "install_bootloader",
            side_effect=ValueError("unexpected configuration issue"),
        ), patch.object(
            self.mod,
            "sync_filesystem",
            side_effect=OSError(errno.EIO, "Simulated final sync I/O error"),
        ), patch(
            "sys.stderr", stderr_buffer
        ):
            with self.assertRaises(ValueError) as ctx:
                self.mod.main([str(toplevel)])

            self.assertEqual(str(ctx.exception), "unexpected configuration issue")
            self.assertIn("Simulated final sync I/O error", stderr_buffer.getvalue())

    def test_main_interruption_triggers_final_sync_and_propagates_unmasked(
        self,
    ) -> None:
        """Verify interruption such as KeyboardInterrupt triggers final sync and propagates unmasked."""
        toplevel = self.temp_dir / "toplevel"
        stderr_buffer = io.StringIO()

        with patch.object(
            self.mod, "install_bootloader", side_effect=KeyboardInterrupt()
        ), patch.object(
            self.mod,
            "sync_filesystem",
            side_effect=OSError(errno.EIO, "Simulated final sync I/O error"),
        ), patch(
            "sys.stderr", stderr_buffer
        ):
            with self.assertRaises(KeyboardInterrupt):
                self.mod.main([str(toplevel)])

            self.assertIn("Simulated final sync I/O error", stderr_buffer.getvalue())


class SproutTomlConfigConformanceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir_obj = tempfile.TemporaryDirectory()
        self.esp_dir = Path(self.temp_dir_obj.name).resolve()
        self.mod = load_sprout_installer(
            self.esp_dir,
            timeout=5,
        )

    def tearDown(self) -> None:
        self.temp_dir_obj.cleanup()

    def _create_sample_entry(
        self,
        identifier: str = "nixos-g1",
        title: str = "NixOS - Generation 1",
        sort_key: str = "nixos-g1",
        kernel_path: str = "EFI/nixos/kernel.efi",
        initrds: tuple[Path, ...] = (Path("EFI/nixos/initrd.efi"),),
        options: tuple[str, ...] = ("init=/nix/store/test-init", "loglevel=4"),
    ) -> Any:
        return self.mod.BootEntry(
            identifier=identifier,
            title=title,
            sort_key=sort_key,
            kernel=Path(kernel_path),
            initrds=initrds,
            options=options,
            artifacts=(),
            critical=True,
        )

    def test_root_and_options_structure(self) -> None:
        """Validate root version and options table against Sprout schema."""
        entry1 = self._create_sample_entry(identifier="nixos-g1", sort_key="nixos-g1")
        entry2 = self._create_sample_entry(identifier="nixos-g2", sort_key="nixos-g2")

        toml_str = self.mod.generate_sprout_config(
            entries=[entry1, entry2],
            default_entry="nixos-g2",
            drivers={},
        )
        data = tomllib.loads(toml_str)

        self.assertEqual(data.get("version"), 1)
        self.assertIn("options", data)
        options = data["options"]
        self.assertEqual(options.get("default-entry"), "nixos-g2")
        self.assertEqual(options.get("menu-timeout"), 5)
        self.assertIsInstance(options.get("menu-timeout"), int)

        # The selected default entry exists in the generated entries
        self.assertIn("entries", data)
        self.assertIn(options["default-entry"], data["entries"])

    def test_zero_timeout_option(self) -> None:
        """Validate options table with a zero timeout."""
        mod_zero = load_sprout_installer(self.esp_dir, timeout=0)
        entry = self._create_sample_entry()

        toml_str = mod_zero.generate_sprout_config(
            entries=[entry],
            default_entry="nixos-g1",
            drivers={},
        )
        data = tomllib.loads(toml_str)

        self.assertEqual(data["options"]["menu-timeout"], 0)
        self.assertIsInstance(data["options"]["menu-timeout"], int)

    def test_drivers_schema_conformance(self) -> None:
        """Validate drivers table against Sprout schema."""
        entry = self._create_sample_entry()
        drivers = {
            "btrfs": Path("EFI/Sprout/drivers/btrfs.efi"),
            "ext4": Path("EFI/Sprout/drivers/ext4.efi"),
        }

        toml_str = self.mod.generate_sprout_config(
            entries=[entry],
            default_entry="nixos-g1",
            drivers=drivers,
        )
        data = tomllib.loads(toml_str)

        self.assertIn("drivers", data)
        self.assertEqual(set(data["drivers"].keys()), {"btrfs", "ext4"})
        self.assertEqual(
            data["drivers"]["btrfs"],
            {"path": r"\EFI\Sprout\drivers\btrfs.efi"},
        )
        self.assertEqual(
            data["drivers"]["ext4"],
            {"path": r"\EFI\Sprout\drivers\ext4.efi"},
        )

    def test_entries_and_actions_schema_conformance(self) -> None:
        """Validate entries and actions tables and their referential integrity."""
        entry1 = self._create_sample_entry(
            identifier="nixos-g1",
            title="NixOS Generation 1",
            sort_key="nixos-g1",
            kernel_path="EFI/nixos/k1.efi",
            options=("init=foo", "quiet"),
        )
        entry2 = self._create_sample_entry(
            identifier="nixos-g2",
            title="NixOS Generation 2",
            sort_key="nixos-g2",
            kernel_path="EFI/nixos/k2.efi",
            options=("init=bar", "loglevel=4"),
        )

        toml_str = self.mod.generate_sprout_config(
            entries=[entry1, entry2],
            default_entry="nixos-g2",
            drivers={},
        )
        data = tomllib.loads(toml_str)

        self.assertIn("entries", data)
        self.assertIn("actions", data)

        for entry in [entry1, entry2]:
            self.assertIn(entry.identifier, data["entries"])
            entry_dict = data["entries"][entry.identifier]
            self.assertEqual(entry_dict["title"], entry.title)
            self.assertEqual(entry_dict["sort-key"], entry.sort_key)
            self.assertIsInstance(entry_dict["actions"], list)
            self.assertEqual(entry_dict["actions"], [entry.identifier])

            # Each referenced action must exist in the actions table
            for action_name in entry_dict["actions"]:
                self.assertIn(action_name, data["actions"])
                action = data["actions"][action_name]
                self.assertIn("chainload", action)
                chainload = action["chainload"]
                self.assertEqual(
                    chainload["path"],
                    self.mod.uefi_path(entry.kernel),
                )
                self.assertEqual(chainload["options"], list(entry.options))

    def test_chainload_initrd_case_none(self) -> None:
        """Validate that with no initrd, neither linux-initrd nor linux-initrd-chain is emitted."""
        entry = self._create_sample_entry(initrds=())

        toml_str = self.mod.generate_sprout_config(
            entries=[entry],
            default_entry=entry.identifier,
            drivers={},
        )
        data = tomllib.loads(toml_str)

        chainload = data["actions"][entry.identifier]["chainload"]
        self.assertNotIn("linux-initrd", chainload)
        self.assertNotIn("linux-initrd-chain", chainload)

    def test_chainload_initrd_case_single(self) -> None:
        """Validate that with one initrd, linux-initrd contains path and linux-initrd-chain is absent."""
        initrd_path = Path("EFI/nixos/main-initrd.efi")
        entry = self._create_sample_entry(initrds=(initrd_path,))

        toml_str = self.mod.generate_sprout_config(
            entries=[entry],
            default_entry=entry.identifier,
            drivers={},
        )
        data = tomllib.loads(toml_str)

        chainload = data["actions"][entry.identifier]["chainload"]
        self.assertEqual(chainload.get("linux-initrd"), r"\EFI\nixos\main-initrd.efi")
        self.assertNotIn("linux-initrd-chain", chainload)

    def test_chainload_initrd_case_multiple(self) -> None:
        """Validate that with multiple initrds, linux-initrd-chain contains ordered paths and linux-initrd is absent."""
        initrds = (
            Path("EFI/nixos/initrd-secrets.efi"),
            Path("EFI/nixos/initrd-extra.efi"),
            Path("EFI/nixos/initrd-main.efi"),
        )
        entry = self._create_sample_entry(initrds=initrds)

        toml_str = self.mod.generate_sprout_config(
            entries=[entry],
            default_entry=entry.identifier,
            drivers={},
        )
        data = tomllib.loads(toml_str)

        chainload = data["actions"][entry.identifier]["chainload"]
        self.assertNotIn("linux-initrd", chainload)
        expected_chain = [
            r"\EFI\nixos\initrd-secrets.efi",
            r"\EFI\nixos\initrd-extra.efi",
            r"\EFI\nixos\initrd-main.efi",
        ]
        self.assertEqual(chainload.get("linux-initrd-chain"), expected_chain)

    def test_toml_quoting_and_uefi_path_escaping(self) -> None:
        """Verify TOML quoting and UEFI escaping with quotes, Unicode, dots, and backslashes."""
        title_with_special_chars = (
            'NixOS "24.11" (Special \'Debug\' & ❄️) [v1.0] \\path\\ test'
        )
        entry = self._create_sample_entry(
            identifier="nixos-special.v1-abc",
            title=title_with_special_chars,
            sort_key="nixos-special.v1",
            kernel_path="EFI/nixos/kernels/linux 6.12.efi",
            options=(
                "init=/nix/store/pkg-test/init",
                'params="key with spaces"',
                "flag",
            ),
        )
        driver_name_with_dots = "vendor.filesystem.btrfs_v2.efi"
        drivers = {
            driver_name_with_dots: Path("EFI/Sprout/drivers/nested/btrfs.efi"),
        }

        toml_str = self.mod.generate_sprout_config(
            entries=[entry],
            default_entry=entry.identifier,
            drivers=drivers,
        )
        data = tomllib.loads(toml_str)

        # Title containing quotes, backslashes, Unicode parses to the exact original string
        self.assertEqual(
            data["entries"][entry.identifier]["title"],
            title_with_special_chars,
        )

        # Driver name containing dots is correctly preserved as a single table key
        self.assertIn(driver_name_with_dots, data["drivers"])
        self.assertEqual(
            data["drivers"][driver_name_with_dots]["path"],
            r"\EFI\Sprout\drivers\nested\btrfs.efi",
        )

        # Kernel options with quotes are parsed without distortion
        chainload = data["actions"][entry.identifier]["chainload"]
        self.assertEqual(
            chainload["options"],
            [
                "init=/nix/store/pkg-test/init",
                'params="key with spaces"',
                "flag",
            ],
        )
        self.assertEqual(
            chainload["path"],
            r"\EFI\nixos\kernels\linux 6.12.efi",
        )

class EspArtifactTransactionAndRetryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir_obj = tempfile.TemporaryDirectory()
        self.temp_dir = Path(self.temp_dir_obj.name).resolve()
        self.esp_dir = self.temp_dir / "esp"
        self.esp_dir.mkdir(parents=True, exist_ok=True)

        self.old_cwd = Path.cwd()
        os.chdir(self.temp_dir)

        self.sprout_source = self.temp_dir / "source-sprout.efi"
        self.sprout_source.write_text("sprout-bin-content")

        self.mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
        )

    def tearDown(self) -> None:
        os.chdir(self.old_cwd)
        self.temp_dir_obj.cleanup()

    def _create_entry(
        self,
        identifier: str,
        generation: int,
        critical: bool = True,
        kernel_data: str = "kernel-data",
        initrd_data: str | None = "initrd-data",
    ) -> Any:
        kernel_src = self.temp_dir / f"kernel-{identifier}.efi"
        kernel_src.write_text(kernel_data)
        dest_k = self.mod.artifact_path("kernel", kernel_src)

        artifacts = [
            self.mod.BootArtifact(
                destination=dest_k,
                source=kernel_src,
                initrd_secrets=None,
                generation=generation,
                critical=critical,
            )
        ]

        initrd_dests = []
        if initrd_data is not None:
            initrd_src = self.temp_dir / f"initrd-{identifier}.img"
            initrd_src.write_text(initrd_data)
            dest_i = self.mod.artifact_path("initrd", initrd_src)
            initrd_dests.append(dest_i)
            artifacts.append(
                self.mod.BootArtifact(
                    destination=dest_i,
                    source=initrd_src,
                    initrd_secrets=None,
                    generation=generation,
                    critical=critical,
                )
            )

        return self.mod.BootEntry(
            identifier=identifier,
            title=f"NixOS {generation}",
            sort_key=f"{generation:020d}",
            kernel=dest_k,
            initrds=tuple(initrd_dests),
            options=("init=/init",),
            artifacts=tuple(artifacts),
            critical=critical,
        )

    def test_partial_artifact_staging_enospc_rolls_back_created_and_preserves_published(
        self,
    ) -> None:
        """Verify ENOSPC while writing subsequent artifact cleans up staged files and leaves published state intact."""
        entry1 = self._create_entry("nixos-g1", 1, kernel_data="k1-bytes", initrd_data="i1-bytes")
        toplevel1 = self.temp_dir / "toplevel1"
        toplevel1.mkdir(parents=True, exist_ok=True)

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry1]
        ):
            self.mod.install_bootloader(toplevel1)

        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        self.assertTrue(config_path.exists())
        orig_config = config_path.read_text()
        dest_k1 = self.esp_dir / entry1.kernel
        dest_i1 = self.esp_dir / entry1.initrds[0]
        self.assertTrue(dest_k1.exists())
        self.assertTrue(dest_i1.exists())

        # Attempt to install generation 2: kernel succeeds, initrd fails with ENOSPC
        entry2 = self._create_entry("nixos-g2", 2, kernel_data="k2-bytes", initrd_data="i2-bytes")
        toplevel2 = self.temp_dir / "toplevel2"
        toplevel2.mkdir(parents=True, exist_ok=True)
        dest_k2 = self.esp_dir / entry2.kernel
        dest_i2 = self.esp_dir / entry2.initrds[0]

        original_atomic_copy = self.mod.atomic_copy

        def failing_atomic_copy(source: Path, destination: Path, replace: bool = False) -> None:
            if destination == dest_i2:
                raise OSError(errno.ENOSPC, "No space left on device")
            original_atomic_copy(source, destination, replace=replace)

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry2, entry1]
        ), patch.object(self.mod, "atomic_copy", side_effect=failing_atomic_copy):
            with self.assertRaises(OSError) as ctx:
                self.mod.install_bootloader(toplevel2)
            self.assertEqual(ctx.exception.errno, errno.ENOSPC)

        # Previously published sprout.toml and referenced generation 1 artifacts are unchanged
        self.assertEqual(config_path.read_text(), orig_config)
        self.assertTrue(dest_k1.exists())
        self.assertTrue(dest_i1.exists())

        # Newly staged generation 2 kernel (copied before failure) was rolled back and removed
        self.assertFalse(dest_k2.exists())
        self.assertFalse(dest_i2.exists())

        # No leftover temporary files
        tmp_files = list(self.esp_dir.rglob("*.tmp"))
        self.assertEqual(tmp_files, [])

    def test_driver_staging_failure_removes_unreferenced_drivers(self) -> None:
        """Verify ENOSPC during driver staging removes unreferenced drivers and preserves prior state."""
        src_btrfs_v1 = self.temp_dir / "driver-btrfs-v1.efi"
        src_btrfs_v1.write_text("btrfs-v1")
        entry1 = self._create_entry("nixos-g1", 1)
        toplevel1 = self.temp_dir / "toplevel1"
        toplevel1.mkdir(parents=True, exist_ok=True)

        mod1 = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers={"btrfs": str(src_btrfs_v1)},
        )
        with patch.object(mod1, "check_mountpoint"), patch.object(
            mod1, "collect_entries", return_value=[entry1]
        ):
            mod1.install_bootloader(toplevel1)

        config_path = self.esp_dir / mod1.SPROUT_CONFIG
        orig_config = config_path.read_text()
        dest_btrfs_v1 = self.esp_dir / mod1.driver_path("btrfs", src_btrfs_v1)
        self.assertTrue(dest_btrfs_v1.exists())

        # Staging with btrfs v2 and ext4: btrfs v2 succeeds, ext4 fails with ENOSPC
        src_btrfs_v2 = self.temp_dir / "driver-btrfs-v2.efi"
        src_btrfs_v2.write_text("btrfs-v2")
        src_ext4 = self.temp_dir / "driver-ext4.efi"
        src_ext4.write_text("ext4-v1")

        mod2 = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers={"btrfs": str(src_btrfs_v2), "ext4": str(src_ext4)},
        )
        dest_btrfs_v2 = self.esp_dir / mod2.driver_path("btrfs", src_btrfs_v2)
        dest_ext4 = self.esp_dir / mod2.driver_path("ext4", src_ext4)

        original_atomic_copy = mod2.atomic_copy

        def failing_atomic_copy(source: Path, destination: Path, replace: bool = False) -> None:
            if destination == dest_ext4:
                raise OSError(errno.ENOSPC, "No space left on device")
            original_atomic_copy(source, destination, replace=replace)

        with patch.object(mod2, "check_mountpoint"), patch.object(
            mod2, "collect_entries", return_value=[entry1]
        ), patch.object(mod2, "atomic_copy", side_effect=failing_atomic_copy):
            with self.assertRaises(OSError) as ctx:
                mod2.install_bootloader(toplevel1)
            self.assertEqual(ctx.exception.errno, errno.ENOSPC)

        # Prior config and v1 driver remain intact
        self.assertEqual(config_path.read_text(), orig_config)
        self.assertTrue(dest_btrfs_v1.exists())

        # Unreferenced btrfs-v2 driver was rolled back
        self.assertFalse(dest_btrfs_v2.exists())
        self.assertFalse(dest_ext4.exists())

    def test_configuration_publication_failure_rolls_back_artifacts_and_loaders(
        self,
    ) -> None:
        """Verify ENOSPC during publication leaves old config/loader intact and cleans up artifacts."""
        entry1 = self._create_entry("nixos-g1", 1, kernel_data="k1-bytes", initrd_data="i1-bytes")
        toplevel1 = self.temp_dir / "toplevel1"
        toplevel1.mkdir(parents=True, exist_ok=True)

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry1]
        ):
            self.mod.install_bootloader(toplevel1)

        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        orig_config = config_path.read_text()
        loader_path = self.esp_dir / self.mod.SPROUT_BINARY
        orig_loader_bytes = loader_path.read_bytes()
        dest_k1 = self.esp_dir / entry1.kernel
        dest_i1 = self.esp_dir / entry1.initrds[0]

        # Prepare generation 2 and update Sprout binary source
        entry2 = self._create_entry("nixos-g2", 2, kernel_data="k2-bytes", initrd_data="i2-bytes")
        toplevel2 = self.temp_dir / "toplevel2"
        toplevel2.mkdir(parents=True, exist_ok=True)
        dest_k2 = self.esp_dir / entry2.kernel
        dest_i2 = self.esp_dir / entry2.initrds[0]
        self.sprout_source.write_text("sprout-bin-v2-updated")

        original_write_text = self.mod.atomic_write_text

        def failing_write_text(dest: Path, contents: str) -> None:
            if dest == config_path:
                raise OSError(errno.ENOSPC, "No space left on device")
            original_write_text(dest, contents)

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry2, entry1]
        ), patch.object(self.mod, "atomic_write_text", side_effect=failing_write_text):
            with self.assertRaises(OSError) as ctx:
                self.mod.install_bootloader(toplevel2)
            self.assertEqual(ctx.exception.errno, errno.ENOSPC)

        # Config and loader are restored/intact
        self.assertEqual(config_path.read_text(), orig_config)
        self.assertEqual(loader_path.read_bytes(), orig_loader_bytes)

        # Generation 1 artifacts remain intact
        self.assertTrue(dest_k1.exists())
        self.assertTrue(dest_i1.exists())

        # Generation 2 artifacts are rolled back
        self.assertFalse(dest_k2.exists())
        self.assertFalse(dest_i2.exists())

    def test_retry_after_failure_converges_cleanly(self) -> None:
        """Verify successful retry after pre-publication failure converges cleanly without leftover orphans."""
        entry1 = self._create_entry("nixos-g1", 1, kernel_data="k1-bytes", initrd_data="i1-bytes")
        toplevel1 = self.temp_dir / "toplevel1"
        toplevel1.mkdir(parents=True, exist_ok=True)

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry1]
        ):
            self.mod.install_bootloader(toplevel1)

        entry2 = self._create_entry("nixos-g2", 2, kernel_data="k2-bytes", initrd_data="i2-bytes")
        toplevel2 = self.temp_dir / "toplevel2"
        toplevel2.mkdir(parents=True, exist_ok=True)
        dest_k2 = self.esp_dir / entry2.kernel
        dest_i2 = self.esp_dir / entry2.initrds[0]

        original_atomic_copy = self.mod.atomic_copy

        def failing_copy(source: Path, destination: Path, replace: bool = False) -> None:
            if destination == dest_i2:
                raise OSError(errno.ENOSPC, "No space left on device")
            original_atomic_copy(source, destination, replace=replace)

        # Step 1: Attempt fails with ENOSPC
        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry2, entry1]
        ), patch.object(self.mod, "atomic_copy", side_effect=failing_copy):
            with self.assertRaises(OSError):
                self.mod.install_bootloader(toplevel2)

        self.assertFalse(dest_k2.exists())
        self.assertFalse(dest_i2.exists())

        # Step 2: Retry with injected failure removed succeeds completely
        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry2, entry1]
        ):
            self.mod.install_bootloader(toplevel2)

        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_text = config_path.read_text()
        self.assertIn("nixos-g2", config_text)
        self.assertIn("default-entry = \"nixos-g2\"", config_text)

        # Both generation 1 and generation 2 artifacts exist and are referenced
        dest_k1 = self.esp_dir / entry1.kernel
        dest_i1 = self.esp_dir / entry1.initrds[0]
        self.assertTrue(dest_k1.exists())
        self.assertTrue(dest_i1.exists())
        self.assertTrue(dest_k2.exists())
        self.assertTrue(dest_i2.exists())

    def test_post_publication_failure_retains_newly_published_artifacts(
        self,
    ) -> None:
        """Verify post-publication sync or NVRAM failure retains all newly published artifacts."""
        entry1 = self._create_entry("nixos-g1", 1, kernel_data="k1-bytes", initrd_data="i1-bytes")
        toplevel1 = self.temp_dir / "toplevel1"
        toplevel1.mkdir(parents=True, exist_ok=True)

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry1]
        ):
            self.mod.install_bootloader(toplevel1)

        entry2 = self._create_entry("nixos-g2", 2, kernel_data="k2-bytes", initrd_data="i2-bytes")
        toplevel2 = self.temp_dir / "toplevel2"
        toplevel2.mkdir(parents=True, exist_ok=True)
        dest_k2 = self.esp_dir / entry2.kernel
        dest_i2 = self.esp_dir / entry2.initrds[0]

        # Case A: Early sync failure after publication
        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry2, entry1]
        ), patch.object(
            self.mod, "sync_filesystem", side_effect=OSError(errno.EIO, "Sync I/O error")
        ):
            with self.assertRaises(OSError) as ctx:
                self.mod.install_bootloader(toplevel2)
            self.assertEqual(ctx.exception.errno, errno.EIO)

        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        self.assertIn("nixos-g2", config_path.read_text())
        self.assertTrue(dest_k2.exists())
        self.assertTrue(dest_i2.exists())

        # Case B: NVRAM failure after publication
        mod_nvram = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            can_touch_efi=True,
        )
        entry3 = self._create_entry("nixos-g3", 3, kernel_data="k3-bytes", initrd_data="i3-bytes")
        toplevel3 = self.temp_dir / "toplevel3"
        toplevel3.mkdir(parents=True, exist_ok=True)
        dest_k3 = self.esp_dir / entry3.kernel
        dest_i3 = self.esp_dir / entry3.initrds[0]

        with patch.object(mod_nvram, "check_mountpoint"), patch.object(
            mod_nvram, "collect_entries", return_value=[entry3, entry2, entry1]
        ), patch.object(
            mod_nvram, "check_efivars"
        ), patch.object(
            mod_nvram, "capture", return_value=""
        ), patch.object(
            mod_nvram,
            "install_nvram_entry",
            side_effect=RuntimeError("simulated NVRAM failure"),
        ):
            with self.assertRaises(RuntimeError) as ctx_nvram:
                mod_nvram.install_bootloader(toplevel3)
            self.assertIn("simulated NVRAM failure", str(ctx_nvram.exception))

        self.assertIn("nixos-g3", config_path.read_text())
        self.assertTrue(dest_k3.exists())
        self.assertTrue(dest_i3.exists())

    def test_cleanup_failure_reports_warning_without_replacing_primary_error(
        self,
    ) -> None:
        """Verify rollback cleanup error logs warning to stderr without replacing primary error or touching pre-existing files."""
        entry1 = self._create_entry("nixos-g1", 1, kernel_data="k1-bytes", initrd_data="i1-bytes")
        toplevel1 = self.temp_dir / "toplevel1"
        toplevel1.mkdir(parents=True, exist_ok=True)

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry1]
        ):
            self.mod.install_bootloader(toplevel1)

        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        orig_config = config_path.read_text()
        dest_k1 = self.esp_dir / entry1.kernel
        dest_i1 = self.esp_dir / entry1.initrds[0]

        entry2 = self._create_entry("nixos-g2", 2, kernel_data="k2-bytes", initrd_data="i2-bytes")
        toplevel2 = self.temp_dir / "toplevel2"
        toplevel2.mkdir(parents=True, exist_ok=True)
        dest_k2 = self.esp_dir / entry2.kernel
        dest_i2 = self.esp_dir / entry2.initrds[0]

        original_atomic_copy = self.mod.atomic_copy

        def failing_copy(source: Path, destination: Path, replace: bool = False) -> None:
            if destination == dest_i2:
                raise OSError(errno.ENOSPC, "No space left on device")
            original_atomic_copy(source, destination, replace=replace)

        original_unlink = os.unlink

        def failing_unlink(path_obj: Any, *args: Any, **kwargs: Any) -> None:
            if Path(path_obj) == dest_k2:
                raise OSError(errno.EPERM, "Operation not permitted")
            original_unlink(path_obj, *args, **kwargs)

        stderr_capture = io.StringIO()
        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry1, entry2]
        ), patch.object(
            self.mod, "atomic_copy", side_effect=failing_copy
        ), patch(
            "os.unlink", side_effect=failing_unlink
        ), patch("sys.stderr", stderr_capture):
            with self.assertRaises(OSError) as ctx:
                self.mod.install_bootloader(toplevel2)
            self.assertEqual(ctx.exception.errno, errno.ENOSPC)

        # Primary error ENOSPC was not masked
        self.assertEqual(ctx.exception.errno, errno.ENOSPC)

        # Warning was reported to stderr
        err_output = stderr_capture.getvalue()
        self.assertIn("warning: failed to clean up uncommitted artifact", err_output)
        self.assertIn("Operation not permitted", err_output)

        # Pre-existing published config and artifacts were not deleted
        self.assertEqual(config_path.read_text(), orig_config)
        self.assertTrue(dest_k1.exists())
        self.assertTrue(dest_i1.exists())

    def test_missing_referenced_file_recreated_during_attempt_is_protected(
        self,
    ) -> None:
        """Verify file referenced by published config that was missing and recreated is protected from rollback."""
        entry1 = self._create_entry("nixos-g1", 1, kernel_data="k1-bytes", initrd_data="i1-bytes")
        toplevel1 = self.temp_dir / "toplevel1"
        toplevel1.mkdir(parents=True, exist_ok=True)

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry1]
        ):
            self.mod.install_bootloader(toplevel1)

        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        orig_config = config_path.read_text()
        dest_k1 = self.esp_dir / entry1.kernel
        dest_i1 = self.esp_dir / entry1.initrds[0]

        # Simulate kernel 1 having been deleted from ESP while still referenced in sprout.toml
        dest_k1.unlink()
        self.assertFalse(dest_k1.exists())

        # Start new installation with gen 1 and gen 2:
        # kernel 1 is recreated, kernel 2 is created, initrd 2 fails with ENOSPC
        entry2 = self._create_entry("nixos-g2", 2, kernel_data="k2-bytes", initrd_data="i2-bytes")
        toplevel2 = self.temp_dir / "toplevel2"
        toplevel2.mkdir(parents=True, exist_ok=True)
        dest_k2 = self.esp_dir / entry2.kernel
        dest_i2 = self.esp_dir / entry2.initrds[0]

        original_atomic_copy = self.mod.atomic_copy

        def failing_copy(source: Path, destination: Path, replace: bool = False) -> None:
            if destination == dest_i2:
                raise OSError(errno.ENOSPC, "No space left on device")
            original_atomic_copy(source, destination, replace=replace)

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry1, entry2]
        ), patch.object(self.mod, "atomic_copy", side_effect=failing_copy):
            with self.assertRaises(OSError) as ctx:
                self.mod.install_bootloader(toplevel2)
            self.assertEqual(ctx.exception.errno, errno.ENOSPC)

        # Kernel 2 (not referenced by published config) was cleaned up
        self.assertFalse(dest_k2.exists())

        # Kernel 1 was protected because published sprout.toml references it
        self.assertTrue(dest_k1.exists())
        self.assertTrue(dest_i1.exists())
        self.assertEqual(config_path.read_text(), orig_config)

    def test_no_existing_sprout_toml_produces_empty_reference_set_and_installs_successfully(
        self,
    ) -> None:
        """Verify absence of previous sprout.toml produces empty reference set and allows clean installation."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        self.assertFalse(config_path.exists())

        refs = self.mod.published_config_referenced_files()
        self.assertEqual(refs, set())

        entry = self._create_entry("nixos-g1", 1, kernel_data="k1-bytes")
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)

        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry]
        ):
            self.mod.install_bootloader(toplevel)

        self.assertTrue(config_path.exists())
        self.assertIn("nixos-g1", config_path.read_text())

    def test_existing_malformed_toml_aborts_before_artifact_staging(self) -> None:
        """Verify malformed sprout.toml raises RuntimeError and aborts installation before staging artifacts."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text("invalid [toml content {{{")

        with self.assertRaises(RuntimeError) as ctx:
            self.mod.published_config_referenced_files()
        self.assertIn("failed to parse published Sprout configuration", str(ctx.exception))

        entry = self._create_entry("nixos-g1", 1, kernel_data="k1-bytes")
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)

        mock_write_boot_files = Mock()
        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry]
        ), patch.object(self.mod, "write_boot_files", mock_write_boot_files):
            with self.assertRaises(RuntimeError) as ctx2:
                self.mod.install_bootloader(toplevel)
            self.assertIn("failed to parse published Sprout configuration", str(ctx2.exception))

        mock_write_boot_files.assert_not_called()
        self.assertEqual(list((self.esp_dir / self.mod.NIXOS_DIR).glob("*.efi")), [])
        self.assertIsNone(self.mod.StagedArtifactTransaction.current())

    def test_existing_unreadable_configuration_aborts_safely(self) -> None:
        """Verify unreadable or invalid configuration file fails safely without staging artifacts."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)

        # Case A: Permission denied / read error
        config_path.write_text("version = 1\n")
        with patch.object(
            Path, "read_text", side_effect=OSError(errno.EACCES, "Permission denied")
        ):
            with self.assertRaises(RuntimeError) as ctx_perm:
                self.mod.published_config_referenced_files()
            self.assertIn("failed to read published Sprout configuration", str(ctx_perm.exception))
            self.assertIn("Permission denied", str(ctx_perm.exception))

        # Case B: Configuration path is a directory instead of a regular file
        config_path.unlink()
        config_path.mkdir(parents=True)
        with self.assertRaises(RuntimeError) as ctx_dir:
            self.mod.published_config_referenced_files()
        self.assertIn("failed to read published Sprout configuration", str(ctx_dir.exception))
        config_path.rmdir()

        # Case C: Configuration is not valid UTF-8
        config_path.write_bytes(b"\x80\x81\x82")
        with self.assertRaises(RuntimeError) as ctx_utf8:
            self.mod.published_config_referenced_files()
        self.assertIn("not valid UTF-8", str(ctx_utf8.exception))

        # Case D: install_bootloader aborts before staging
        entry = self._create_entry("nixos-g1", 1, kernel_data="k1-bytes")
        toplevel = self.temp_dir / "toplevel"
        toplevel.mkdir(parents=True, exist_ok=True)

        mock_write_boot_files = Mock()
        with patch.object(self.mod, "check_mountpoint"), patch.object(
            self.mod, "collect_entries", return_value=[entry]
        ), patch.object(self.mod, "write_boot_files", mock_write_boot_files):
            with self.assertRaises(RuntimeError) as ctx_install:
                self.mod.install_bootloader(toplevel)
            self.assertIn("not valid UTF-8", str(ctx_install.exception))

        mock_write_boot_files.assert_not_called()
        self.assertIsNone(self.mod.StagedArtifactTransaction.current())

    def test_transaction_entry_failure_does_not_leave_stale_active_reference(
        self,
    ) -> None:
        """Verify exception during StagedArtifactTransaction.__enter__ does not leave a stale active reference."""
        self.assertIsNone(self.mod.StagedArtifactTransaction.current())

        with patch.object(
            self.mod,
            "published_config_referenced_files",
            side_effect=RuntimeError("simulated config inspection error"),
        ):
            tx = self.mod.StagedArtifactTransaction()
            with self.assertRaises(RuntimeError) as ctx:
                with tx:
                    pass
            self.assertIn("simulated config inspection error", str(ctx.exception))

        self.assertIsNone(self.mod.StagedArtifactTransaction.current())

        # Verify a subsequent transaction can enter cleanly without "already active" error
        with self.mod.StagedArtifactTransaction() as second_tx:
            self.assertIs(self.mod.StagedArtifactTransaction.current(), second_tx)

        self.assertIsNone(self.mod.StagedArtifactTransaction.current())

    def test_invalid_schema_in_existing_sprout_toml_aborts_safely(self) -> None:
        """Verify invalid table structures or unsafe paths in existing sprout.toml fail safely."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)

        # Invalid drivers table
        config_path.write_text("version = 1\ndrivers = 'not-a-table'\n")
        with self.assertRaises(RuntimeError) as ctx1:
            self.mod.published_config_referenced_files()
        self.assertIn("invalid 'drivers' table", str(ctx1.exception))

        # Invalid driver entry
        config_path.write_text("version = 1\n[drivers.btrfs]\npath = 12345\n")
        with self.assertRaises(RuntimeError) as ctx2:
            self.mod.published_config_referenced_files()
        self.assertIn("missing or non-string path", str(ctx2.exception))

        # Invalid actions table
        config_path.write_text("version = 1\nactions = 999\n")
        with self.assertRaises(RuntimeError) as ctx3:
            self.mod.published_config_referenced_files()
        self.assertIn("invalid 'actions' table", str(ctx3.exception))

        # Invalid action chainload table
        config_path.write_text("version = 1\n[actions.entry1]\nchainload = 'not-a-table'\n")
        with self.assertRaises(RuntimeError) as ctx4:
            self.mod.published_config_referenced_files()
        self.assertIn("invalid 'chainload' table", str(ctx4.exception))

        # Unsafe relative path in chainload (attempting path traversal)
        config_path.write_text("version = 1\n[actions.entry1.chainload]\npath = '../../etc/passwd'\n")
        with self.assertRaises(RuntimeError) as ctx5:
            self.mod.published_config_referenced_files()
        self.assertIn("references invalid kernel path", str(ctx5.exception))

    def test_version_validation_accepts_one_and_rejects_missing_unsupported_non_integer(
        self,
    ) -> None:
        """Verify published configuration version must be integer 1."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)

        # Valid version = 1
        config_path.write_text("version = 1\n")
        self.assertEqual(self.mod.published_config_referenced_files(), set())

        # Missing version
        config_path.write_text("[options]\ndefault-entry = 'foo'\n")
        with self.assertRaises(RuntimeError) as ctx_missing:
            self.mod.published_config_referenced_files()
        self.assertIn("missing 'version' field", str(ctx_missing.exception))

        # String version "1"
        config_path.write_text("version = '1'\n")
        with self.assertRaises(RuntimeError) as ctx_str:
            self.mod.published_config_referenced_files()
        self.assertIn("unsupported or invalid version '1'; expected 1", str(ctx_str.exception))

        # Float version 1.0
        config_path.write_text("version = 1.0\n")
        with self.assertRaises(RuntimeError) as ctx_float:
            self.mod.published_config_referenced_files()
        self.assertIn("unsupported or invalid version 1.0; expected 1", str(ctx_float.exception))

        # Boolean version true
        config_path.write_text("version = true\n")
        with self.assertRaises(RuntimeError) as ctx_bool:
            self.mod.published_config_referenced_files()
        self.assertIn("unsupported or invalid version True; expected 1", str(ctx_bool.exception))

        # Unsupported version integer 0
        config_path.write_text("version = 0\n")
        with self.assertRaises(RuntimeError) as ctx_v0:
            self.mod.published_config_referenced_files()
        self.assertIn("unsupported or invalid version 0; expected 1", str(ctx_v0.exception))

        # Unsupported version integer 2
        config_path.write_text("version = 2\n")
        with self.assertRaises(RuntimeError) as ctx_v2:
            self.mod.published_config_referenced_files()
        self.assertIn("unsupported or invalid version 2; expected 1", str(ctx_v2.exception))

    def test_edera_action_paths_collected_and_protected_on_rollback(self) -> None:
        """Verify edera action paths (xen, kernel, initrd, initrd-chain) are collected and protected."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)

        config_path.write_text(
            "version = 1\n"
            "[actions.edera_boot.edera]\n"
            "xen = 'EFI/edera/xen.efi'\n"
            "kernel = 'EFI/nixos/kernel-edera.efi'\n"
            "initrd = 'EFI/nixos/initrd-edera.img'\n"
            "xen-options = ['console=com1']\n"
            "kernel-options = ['quiet']\n"
        )
        refs = self.mod.published_config_referenced_files()
        expected = {
            self.esp_dir / "EFI/edera/xen.efi",
            self.esp_dir / "EFI/nixos/kernel-edera.efi",
            self.esp_dir / "EFI/nixos/initrd-edera.img",
        }
        self.assertEqual(refs, expected)

        # Pre-create the edera files on ESP
        for p in expected:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("existing-content")

        # Verify StagedArtifactTransaction protects them if recreated during staging
        with self.assertRaises(RuntimeError):
            with self.mod.StagedArtifactTransaction() as tx:
                # Attempt to record an existing published edera file as created
                tx.record_created(self.esp_dir / "EFI/edera/xen.efi")
                # Create and record a completely new file
                new_file = self.esp_dir / "EFI/nixos/staged-temp.efi"
                new_file.write_text("staged-temp-content")
                tx.record_created(new_file)
                raise RuntimeError("simulated staging failure")

        # Rollback should delete new_file but PRESERVE existing published edera file
        self.assertFalse(new_file.exists())
        self.assertTrue((self.esp_dir / "EFI/edera/xen.efi").exists())
        self.assertEqual(
            (self.esp_dir / "EFI/edera/xen.efi").read_text(),
            "existing-content",
        )

        # Test edera with initrd-chain
        config_path.write_text(
            "version = 1\n"
            "[actions.edera_boot2.edera]\n"
            "xen = 'EFI/xen2.efi'\n"
            "kernel = 'EFI/kernel2.efi'\n"
            "initrd-chain = ['EFI/initrd-base.img', 'EFI/initrd-extra.img']\n"
        )
        refs2 = self.mod.published_config_referenced_files()
        expected2 = {
            self.esp_dir / "EFI/xen2.efi",
            self.esp_dir / "EFI/kernel2.efi",
            self.esp_dir / "EFI/initrd-base.img",
            self.esp_dir / "EFI/initrd-extra.img",
        }
        self.assertEqual(refs2, expected2)

    def test_edera_and_chainload_schema_validation_aborts_safely(self) -> None:
        """Verify invalid edera and chainload schemas fail safely with clear RuntimeError."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)

        # Edera missing xen
        config_path.write_text("version = 1\n[actions.e.edera]\nkernel = 'EFI/kernel.efi'\n")
        with self.assertRaises(RuntimeError) as ctx1:
            self.mod.published_config_referenced_files()
        self.assertIn("edera xen path is missing or not a string", str(ctx1.exception))

        # Edera non-string xen
        config_path.write_text("version = 1\n[actions.e.edera]\nxen = 123\nkernel = 'EFI/k.efi'\n")
        with self.assertRaises(RuntimeError) as ctx2:
            self.mod.published_config_referenced_files()
        self.assertIn("edera xen path is missing or not a string", str(ctx2.exception))

        # Edera missing kernel
        config_path.write_text("version = 1\n[actions.e.edera]\nxen = 'EFI/xen.efi'\n")
        with self.assertRaises(RuntimeError) as ctx3:
            self.mod.published_config_referenced_files()
        self.assertIn("edera kernel path is missing or not a string", str(ctx3.exception))

        # Edera non-string kernel
        config_path.write_text("version = 1\n[actions.e.edera]\nxen = 'EFI/xen.efi'\nkernel = ['k']\n")
        with self.assertRaises(RuntimeError) as ctx4:
            self.mod.published_config_referenced_files()
        self.assertIn("edera kernel path is missing or not a string", str(ctx4.exception))

        # Edera specifying both initrd and initrd-chain
        config_path.write_text(
            "version = 1\n[actions.e.edera]\nxen = 'EFI/x.efi'\nkernel = 'EFI/k.efi'\n"
            "initrd = 'EFI/init.img'\ninitrd-chain = ['EFI/init2.img']\n"
        )
        with self.assertRaises(RuntimeError) as ctx5:
            self.mod.published_config_referenced_files()
        self.assertIn("cannot specify both 'initrd' and 'initrd-chain' in edera", str(ctx5.exception))

        # Edera non-string initrd
        config_path.write_text(
            "version = 1\n[actions.e.edera]\nxen = 'EFI/x.efi'\nkernel = 'EFI/k.efi'\ninitrd = 99\n"
        )
        with self.assertRaises(RuntimeError) as ctx6:
            self.mod.published_config_referenced_files()
        self.assertIn("edera initrd path is not a string", str(ctx6.exception))

        # Edera non-list initrd-chain
        config_path.write_text(
            "version = 1\n[actions.e.edera]\nxen = 'EFI/x.efi'\nkernel = 'EFI/k.efi'\ninitrd-chain = 'str'\n"
        )
        with self.assertRaises(RuntimeError) as ctx7:
            self.mod.published_config_referenced_files()
        self.assertIn("edera initrd chain is not a list", str(ctx7.exception))

        # Edera non-string item in initrd-chain
        config_path.write_text(
            "version = 1\n[actions.e.edera]\nxen = 'EFI/x.efi'\nkernel = 'EFI/k.efi'\ninitrd-chain = ['EFI/init.img', 42]\n"
        )
        with self.assertRaises(RuntimeError) as ctx8:
            self.mod.published_config_referenced_files()
        self.assertIn("edera initrd chain item 1 is not a string", str(ctx8.exception))

        # Edera path traversal
        config_path.write_text(
            "version = 1\n[actions.e.edera]\nxen = '../../xen.efi'\nkernel = 'EFI/k.efi'\n"
        )
        with self.assertRaises(RuntimeError) as ctx9:
            self.mod.published_config_referenced_files()
        self.assertIn("references invalid edera xen path", str(ctx9.exception))

        # Chainload specifying both linux-initrd and linux-initrd-chain
        config_path.write_text(
            "version = 1\n[actions.entry1.chainload]\npath = 'EFI/kernel.efi'\n"
            "linux-initrd = 'EFI/initrd.img'\nlinux-initrd-chain = ['EFI/chain.img']\n"
        )
        with self.assertRaises(RuntimeError) as ctx10:
            self.mod.published_config_referenced_files()
        self.assertIn("cannot specify both 'linux-initrd' and 'linux-initrd-chain'", str(ctx10.exception))

    def test_dynamic_variable_substitution_and_unresolved_variable_rejection(self) -> None:
        """Verify root [values] substitution, longest-key priority, and rejection of unresolved variables."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)

        # Successful resolution with longest-key priority
        config_path.write_text(
            "version = 1\n"
            "[values]\n"
            "sub = 'nixos'\n"
            "gen = '42'\n"
            "prefix = 'short'\n"
            "prefix_long = 'matched_long'\n"
            "\n"
            "[drivers.drv]\n"
            "path = 'EFI/Sprout/drivers/$prefix_long.efi'\n"
            "\n"
            "[actions.boot.chainload]\n"
            "path = 'EFI/$sub/kernel-$gen.efi'\n"
            "linux-initrd = 'EFI/$sub/initrd-$gen.img'\n"
        )
        refs = self.mod.published_config_referenced_files()
        expected = {
            self.esp_dir / "EFI/Sprout/drivers/matched_long.efi",
            self.esp_dir / "EFI/nixos/kernel-42.efi",
            self.esp_dir / "EFI/nixos/initrd-42.img",
        }
        self.assertEqual(refs, expected)

        # Unresolved variable in driver path
        config_path.write_text(
            "version = 1\n"
            "[drivers.btrfs]\n"
            "path = 'EFI/drivers/$unresolved_driver.efi'\n"
        )
        with self.assertRaises(RuntimeError) as ctx_drv:
            self.mod.published_config_referenced_files()
        self.assertIn("contains unresolved dynamic variable '$unresolved_driver'", str(ctx_drv.exception))

        # Unresolved variable in chainload path
        config_path.write_text(
            "version = 1\n"
            "[actions.boot.chainload]\n"
            "path = 'EFI/nixos/kernel-$missing_gen.efi'\n"
        )
        with self.assertRaises(RuntimeError) as ctx_cl:
            self.mod.published_config_referenced_files()
        self.assertIn("contains unresolved dynamic variable '$missing_gen'", str(ctx_cl.exception))

        # Unresolved variable in edera path
        config_path.write_text(
            "version = 1\n"
            "[actions.e.edera]\n"
            "xen = 'EFI/$xen_image.efi'\n"
            "kernel = 'EFI/kernel.efi'\n"
        )
        with self.assertRaises(RuntimeError) as ctx_ed:
            self.mod.published_config_referenced_files()
        self.assertIn("contains unresolved dynamic variable '$xen_image'", str(ctx_ed.exception))

        # Invalid values table
        config_path.write_text("version = 1\nvalues = 'not-a-table'\n")
        with self.assertRaises(RuntimeError) as ctx_vt:
            self.mod.published_config_referenced_files()
        self.assertIn("invalid 'values' table", str(ctx_vt.exception))

        # Invalid values table entry (non-string)
        config_path.write_text("version = 1\n[values]\nkey = 1234\n")
        with self.assertRaises(RuntimeError) as ctx_ve:
            self.mod.published_config_referenced_files()
        self.assertIn("invalid 'values' table entry 'key'", str(ctx_ve.exception))

    def test_dynamic_generation_constructs_rejected_safely(self) -> None:
        """Verify configurations using generators or extractors fail safely."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)

        # Non-empty generators
        config_path.write_text(
            "version = 1\n"
            "[generators.matrix]\n"
            "kernel = ['vmlinuz-1', 'vmlinuz-2']\n"
        )
        with self.assertRaises(RuntimeError) as ctx_gen:
            self.mod.published_config_referenced_files()
        self.assertIn("contains unsupported dynamic 'generators'", str(ctx_gen.exception))

        # Non-empty extractors
        config_path.write_text(
            "version = 1\n"
            "[extractors.scan]\n"
            "path = 'EFI/nixos'\n"
        )
        with self.assertRaises(RuntimeError) as ctx_ext:
            self.mod.published_config_referenced_files()
        self.assertIn("contains unsupported dynamic 'extractors'", str(ctx_ext.exception))

        # Empty generators and extractors tables should be accepted
        config_path.write_text(
            "version = 1\n"
            "generators = {}\n"
            "extractors = {}\n"
        )
        self.assertEqual(self.mod.published_config_referenced_files(), set())

        # Invalid generators table type
        config_path.write_text("version = 1\ngenerators = 'not-a-table'\n")
        with self.assertRaises(RuntimeError) as ctx_gen_inv:
            self.mod.published_config_referenced_files()
        self.assertIn("invalid 'generators' table", str(ctx_gen_inv.exception))

        # Invalid extractors table type
        config_path.write_text("version = 1\nextractors = 'not-a-table'\n")
        with self.assertRaises(RuntimeError) as ctx_ext_inv:
            self.mod.published_config_referenced_files()
        self.assertIn("invalid 'extractors' table", str(ctx_ext_inv.exception))

    def test_entry_scoped_values_override_root_values_and_protect_actual_paths(self) -> None:
        """Verify entry-scoped values override root values for chainload paths and lower-priority paths are not protected."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)

        config_path.write_text(
            "version = 1\n"
            "[values]\n"
            "k_name = 'root-kernel.efi'\n"
            "\n"
            "[entries.g1]\n"
            "title = 'NixOS 1'\n"
            "actions = ['boot']\n"
            "values = { k_name = 'entry-kernel.efi' }\n"
            "\n"
            "[actions.boot.chainload]\n"
            "path = 'EFI/nixos/$k_name'\n"
        )
        refs = self.mod.published_config_referenced_files()
        expected_entry_path = self.esp_dir / "EFI/nixos/entry-kernel.efi"
        lower_priority_root_path = self.esp_dir / "EFI/nixos/root-kernel.efi"

        self.assertIn(expected_entry_path, refs)
        self.assertNotIn(lower_priority_root_path, refs)

        # Pre-create both files on ESP
        expected_entry_path.parent.mkdir(parents=True, exist_ok=True)
        expected_entry_path.write_text("entry-kernel-data")
        lower_priority_root_path.write_text("root-kernel-data")

        # In a failed transaction, expected_entry_path is protected, while lower_priority_root_path is NOT
        with self.assertRaises(RuntimeError):
            with self.mod.StagedArtifactTransaction() as tx:
                tx.record_created(expected_entry_path)
                tx.record_created(lower_priority_root_path)
                raise RuntimeError("simulated failure")

        self.assertTrue(expected_entry_path.exists())
        self.assertFalse(lower_priority_root_path.exists())

        # Unresolved dynamic variable in entry-scoped values fails safely before staging
        config_path.write_text(
            "version = 1\n"
            "[entries.g1]\n"
            "title = 'NixOS 1'\n"
            "actions = ['boot']\n"
            "values = { k_name = '$missing_val' }\n"
            "\n"
            "[actions.boot.chainload]\n"
            "path = 'EFI/nixos/$k_name'\n"
        )
        with self.assertRaises(RuntimeError) as ctx_unres:
            self.mod.published_config_referenced_files()
        self.assertIn("contains unresolved dynamic variable '$missing_val'", str(ctx_unres.exception))

        # Dynamic variable in entry action reference
        config_path.write_text(
            "version = 1\n"
            "[values]\n"
            "act = 'boot'\n"
            "\n"
            "[entries.g1]\n"
            "title = 'NixOS 1'\n"
            "actions = ['$act']\n"
            "\n"
            "[actions.boot.chainload]\n"
            "path = 'EFI/nixos/kernel.efi'\n"
        )
        refs_dyn_act = self.mod.published_config_referenced_files()
        self.assertIn(self.esp_dir / "EFI/nixos/kernel.efi", refs_dyn_act)

        # Unresolved dynamic variable in entry action reference
        config_path.write_text(
            "version = 1\n"
            "[entries.g1]\n"
            "title = 'NixOS 1'\n"
            "actions = ['$unknown_act']\n"
            "\n"
            "[actions.boot.chainload]\n"
            "path = 'EFI/nixos/kernel.efi'\n"
        )
        with self.assertRaises(RuntimeError) as ctx_unres_act:
            self.mod.published_config_referenced_files()
        self.assertIn("contains unresolved dynamic variable '$unknown_act'", str(ctx_unres_act.exception))

    def test_phase_scoped_values_and_actions_handled_safely(self) -> None:
        """Verify phase-scoped values protect actual paths and lower-priority values are not used."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)

        config_path.write_text(
            "version = 1\n"
            "[values]\n"
            "xen_bin = 'xen-default.efi'\n"
            "\n"
            "[[phases.early]]\n"
            "actions = ['boot_hv']\n"
            "values = { xen_bin = 'xen-phase.efi' }\n"
            "\n"
            "[actions.boot_hv.edera]\n"
            "xen = 'EFI/edera/$xen_bin'\n"
            "kernel = 'EFI/nixos/kernel.efi'\n"
        )
        refs = self.mod.published_config_referenced_files()
        expected_phase_path = self.esp_dir / "EFI/edera/xen-phase.efi"
        lower_priority_root_path = self.esp_dir / "EFI/edera/xen-default.efi"

        self.assertIn(expected_phase_path, refs)
        self.assertNotIn(lower_priority_root_path, refs)

        # Unresolved dynamic variable in phase-scoped action
        config_path.write_text(
            "version = 1\n"
            "[[phases.startup]]\n"
            "actions = ['boot_hv']\n"
            "values = { xen_bin = '$missing_xen' }\n"
            "\n"
            "[actions.boot_hv.edera]\n"
            "xen = 'EFI/edera/$xen_bin'\n"
            "kernel = 'EFI/nixos/kernel.efi'\n"
        )
        with self.assertRaises(RuntimeError) as ctx_phase_unres:
            self.mod.published_config_referenced_files()
        self.assertIn("contains unresolved dynamic variable '$missing_xen'", str(ctx_phase_unres.exception))

        # Unknown phase name is rejected
        config_path.write_text(
            "version = 1\n"
            "[[phases.unsupported_phase]]\n"
            "actions = ['boot_hv']\n"
        )
        with self.assertRaises(RuntimeError) as ctx_unknown_phase:
            self.mod.published_config_referenced_files()
        self.assertIn("contains unknown phase 'unsupported_phase'", str(ctx_unknown_phase.exception))

        # Phase item not a table
        config_path.write_text(
            "version = 1\n"
            "[phases]\n"
            "early = ['not-a-table']\n"
        )
        with self.assertRaises(RuntimeError) as ctx_phase_item_inv:
            self.mod.published_config_referenced_files()
        self.assertIn("is not a table", str(ctx_phase_item_inv.exception))

    def test_chainload_devicetree_paths_protected_or_aborts_safely(self) -> None:
        """Verify chainload.devicetree paths are protected and invalid configurations fail safely."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)

        # Valid devicetree path
        config_path.write_text(
            "version = 1\n"
            "[values]\n"
            "board = 'rockchip'\n"
            "\n"
            "[actions.boot.chainload]\n"
            "path = 'EFI/nixos/kernel.efi'\n"
            "devicetree = 'EFI/dtbs/$board/rk3588.dtb'\n"
        )
        refs = self.mod.published_config_referenced_files()
        expected_dtb = self.esp_dir / "EFI/dtbs/rockchip/rk3588.dtb"
        self.assertIn(expected_dtb, refs)

        # Pre-create dtb file on ESP and verify protection during transaction rollback
        expected_dtb.parent.mkdir(parents=True, exist_ok=True)
        expected_dtb.write_text("dtb-content")
        with self.assertRaises(RuntimeError):
            with self.mod.StagedArtifactTransaction() as tx:
                tx.record_created(expected_dtb)
                raise RuntimeError("simulated failure")
        self.assertTrue(expected_dtb.exists())

        # Non-string devicetree path
        config_path.write_text(
            "version = 1\n"
            "[actions.boot.chainload]\n"
            "path = 'EFI/nixos/kernel.efi'\n"
            "devicetree = 9999\n"
        )
        with self.assertRaises(RuntimeError) as ctx_dt_str:
            self.mod.published_config_referenced_files()
        self.assertIn("devicetree path is not a string", str(ctx_dt_str.exception))

        # Path traversal in devicetree
        config_path.write_text(
            "version = 1\n"
            "[actions.boot.chainload]\n"
            "path = 'EFI/nixos/kernel.efi'\n"
            "devicetree = '../../evil.dtb'\n"
        )
        with self.assertRaises(RuntimeError) as ctx_dt_trav:
            self.mod.published_config_referenced_files()
        self.assertIn("references invalid devicetree path", str(ctx_dt_trav.exception))

        # Unresolved dynamic variable in devicetree
        config_path.write_text(
            "version = 1\n"
            "[actions.boot.chainload]\n"
            "path = 'EFI/nixos/kernel.efi'\n"
            "devicetree = 'EFI/dtbs/$missing_board.dtb'\n"
        )
        with self.assertRaises(RuntimeError) as ctx_dt_unres:
            self.mod.published_config_referenced_files()
        self.assertIn("contains unresolved dynamic variable '$missing_board'", str(ctx_dt_unres.exception))

    def test_options_autoconfigure_fails_closed_before_staging(self) -> None:
        """Verify options.autoconfigure = true fails closed to prevent unprotected dynamic references."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)

        # options.autoconfigure = true fails closed
        config_path.write_text("version = 1\n[options]\nautoconfigure = true\n")
        with self.assertRaises(RuntimeError) as ctx_ac_true:
            self.mod.published_config_referenced_files()
        self.assertIn("enables 'options.autoconfigure'", str(ctx_ac_true.exception))

        # options.autoconfigure = false evaluates cleanly
        config_path.write_text("version = 1\n[options]\nautoconfigure = false\n")
        self.assertEqual(self.mod.published_config_referenced_files(), set())

        # options.autoconfigure non-boolean is rejected
        config_path.write_text("version = 1\n[options]\nautoconfigure = 'yes'\n")
        with self.assertRaises(RuntimeError) as ctx_ac_type:
            self.mod.published_config_referenced_files()
        self.assertIn("'options.autoconfigure' is not a boolean", str(ctx_ac_type.exception))

        # root-level autoconfigure = true fails closed
        config_path.write_text("version = 1\nautoconfigure = true\n")
        with self.assertRaises(RuntimeError) as ctx_ac_root:
            self.mod.published_config_referenced_files()
        self.assertIn("enables 'autoconfigure'", str(ctx_ac_root.exception))

    def test_nested_value_resolution_and_cycle_rejection(self) -> None:
        """Verify nested value expansion works iteratively, and cycles/length limits abort safely."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)

        # Multi-hop nested value expansion
        config_path.write_text(
            "version = 1\n"
            "[values]\n"
            "v_base = 'EFI'\n"
            "v_os = '$v_base/nixos'\n"
            "v_k = '$v_os/kernel-nested.efi'\n"
            "\n"
            "[actions.boot.chainload]\n"
            "path = '$v_k'\n"
        )
        refs = self.mod.published_config_referenced_files()
        self.assertIn(self.esp_dir / "EFI/nixos/kernel-nested.efi", refs)

        # Nested root value overridden by entry context
        config_path.write_text(
            "version = 1\n"
            "[values]\n"
            "v_base = 'EFI'\n"
            "v_k = '$v_base/kernel-inherited.efi'\n"
            "\n"
            "[entries.e1]\n"
            "title = 'E1'\n"
            "actions = ['boot']\n"
            "values = { v_base = 'ESP' }\n"
            "\n"
            "[actions.boot.chainload]\n"
            "path = '$v_k'\n"
        )
        refs_overridden = self.mod.published_config_referenced_files()
        self.assertIn(self.esp_dir / "ESP/kernel-inherited.efi", refs_overridden)
        self.assertNotIn(self.esp_dir / "EFI/kernel-inherited.efi", refs_overridden)

        # Multi-pass resolution exceeding iteration limit bails safely
        config_path.write_text(
            "version = 1\n"
            "[values]\n"
            "x = '$y'\n"
            "y = '$z'\n"
            "z = 'resolved'\n"
        )
        with patch.object(self.mod, "CONTEXT_FINALIZE_ITERATION_LIMIT", 1):
            with self.assertRaises(RuntimeError) as ctx_cycle:
                self.mod.published_config_referenced_files()
            self.assertIn("maximum number of replacement iterations reached", str(ctx_cycle.exception))

        # Direct cycle / unresolvable reference bails with resolution cannot be completed
        config_path.write_text(
            "version = 1\n"
            "[values]\n"
            "cycle_a = '$cycle_b'\n"
            "cycle_b = '$cycle_a'\n"
        )
        with self.assertRaises(RuntimeError) as ctx_direct:
            self.mod.published_config_referenced_files()
        self.assertIn("resolution cannot be completed", str(ctx_direct.exception))

        # Value length blowup bails on value length limit
        config_path.write_text(
            "version = 1\n"
            "[values]\n"
            "grow = 'x$grow$grow'\n"
        )
        with self.assertRaises(RuntimeError) as ctx_grow:
            self.mod.published_config_referenced_files()
        self.assertIn("too long while finalizing", str(ctx_grow.exception))


class SproutStaticSettingsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir_obj = tempfile.TemporaryDirectory()
        self.temp_dir = Path(self.temp_dir_obj.name).resolve()
        self.esp_dir = self.temp_dir / "esp"
        self.esp_dir.mkdir(parents=True, exist_ok=True)

        self.old_cwd = Path.cwd()
        os.chdir(self.temp_dir)

        self.driver_src = self.temp_dir / "btrfs-driver.efi"
        self.driver_src.write_text("driver-initial")

        self.sprout_source = self.temp_dir / "source-sprout.efi"
        self.sprout_source.write_text("sprout-bin")

        self.drivers_config = {
            "btrfs": str(self.driver_src),
        }

    def tearDown(self) -> None:
        os.chdir(self.old_cwd)
        self.temp_dir_obj.cleanup()

    def _create_sample_entry(
        self,
        mod: ModuleType,
        identifier: str = "nixos-g1",
        generation: int = 1,
        title: str = "NixOS generation 1",
    ) -> Any:
        k = self.temp_dir / f"kernel-{identifier}.efi"
        k.write_text("kernel-bytes")
        dest_k = mod.NIXOS_DIR / f"{identifier}-kernel.efi"
        art_k = mod.BootArtifact(dest_k, k, None, generation, True)
        return mod.BootEntry(
            identifier=identifier,
            title=title,
            sort_key=identifier,
            kernel=dest_k,
            initrds=(),
            options=("init=/init",),
            artifacts=(art_k,),
            critical=True,
        )

    def test_final_toml_contains_generated_and_custom_entries_and_actions(self) -> None:
        """Verify published sprout.toml includes both NixOS entries and custom entries/actions with options."""
        shell_efi = self.esp_dir / "EFI" / "tools" / "Shell.efi"
        shell_efi.parent.mkdir(parents=True, exist_ok=True)
        shell_efi.write_text("shell-binary")

        settings = {
            "options": {
                "menu-style": "simple",
            },
            "entries": {
                "uefi-shell": {
                    "title": "UEFI Shell",
                    "actions": ["uefi-shell"],
                    "sort-key": "z-shell",
                    "values": {"theme": "dark"},
                },
            },
            "actions": {
                "uefi-shell": {
                    "chainload": {
                        "path": r"\EFI\tools\Shell.efi",
                        "options": ["-nomap"],
                    },
                },
            },
        }

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers=self.drivers_config,
            timeout=10,
            settings=settings,
        )

        entry = self._create_sample_entry(mod)
        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ):
            mod.install_bootloader(self.temp_dir)

        config_path = self.esp_dir / mod.SPROUT_CONFIG
        self.assertTrue(config_path.is_file())
        data = tomllib.loads(config_path.read_text(encoding="utf-8"))

        self.assertEqual(data["version"], 1)
        # Module-owned options
        self.assertEqual(data["options"]["default-entry"], "nixos-g1")
        self.assertEqual(data["options"]["menu-timeout"], 10)
        # Custom option
        self.assertEqual(data["options"]["menu-style"], "simple")
        # Drivers
        self.assertIn("btrfs", data["drivers"])
        # Entries
        self.assertIn("nixos-g1", data["entries"])
        self.assertIn("uefi-shell", data["entries"])
        self.assertEqual(data["entries"]["uefi-shell"]["title"], "UEFI Shell")
        self.assertEqual(data["entries"]["uefi-shell"]["actions"], ["uefi-shell"])
        self.assertEqual(data["entries"]["uefi-shell"]["sort-key"], "z-shell")
        self.assertEqual(data["entries"]["uefi-shell"]["values"]["theme"], "dark")
        # Actions
        self.assertIn("nixos-g1", data["actions"])
        self.assertIn("uefi-shell", data["actions"])
        self.assertEqual(
            data["actions"]["uefi-shell"]["chainload"]["path"],
            r"\EFI\tools\Shell.efi",
        )
        self.assertEqual(
            data["actions"]["uefi-shell"]["chainload"]["options"],
            ["-nomap"],
        )

    def test_toml_roundtrip_with_quotes_backslashes_and_non_ascii(self) -> None:
        """Verify arbitrary strings including quotes, backslashes, and Unicode roundtrip through tomllib."""
        special_file = self.esp_dir / "EFI" / "special.efi"
        special_file.parent.mkdir(parents=True, exist_ok=True)
        special_file.write_text("special")

        settings = {
            "entries": {
                "custom-entry": {
                    "title": 'Special "Title" \\ with newline \n and 中文',
                    "actions": ["custom-action"],
                    "values": {
                        'key "with" quotes': "value \\ with backslash and 日本語",
                    },
                },
            },
            "actions": {
                "custom-action": {
                    "chainload": {
                        "path": r"\EFI\special.efi",
                        "options": ['init="quoted arg"', "label=测试"],
                    },
                },
            },
        }

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers=self.drivers_config,
            settings=settings,
        )

        entry = self._create_sample_entry(mod)
        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ):
            mod.install_bootloader(self.temp_dir)

        config_path = self.esp_dir / mod.SPROUT_CONFIG
        data = tomllib.loads(config_path.read_text(encoding="utf-8"))

        entry_data = data["entries"]["custom-entry"]
        self.assertEqual(
            entry_data["title"],
            'Special "Title" \\ with newline \n and 中文',
        )
        self.assertEqual(
            entry_data["values"]['key "with" quotes'],
            "value \\ with backslash and 日本語",
        )
        cl_data = data["actions"]["custom-action"]["chainload"]
        self.assertEqual(
            cl_data["options"],
            ['init="quoted arg"', "label=测试"],
        )

    def test_custom_action_variants_serialization(self) -> None:
        """Verify chainload, print, and edera action variants serialize correctly."""
        xen_file = self.esp_dir / "EFI" / "xen.efi"
        xen_file.parent.mkdir(parents=True, exist_ok=True)
        xen_file.write_text("xen")
        kernel_file = self.esp_dir / "EFI" / "vmlinuz.efi"
        kernel_file.write_text("kernel")
        initrd_file = self.esp_dir / "EFI" / "initrd.img"
        initrd_file.write_text("initrd")

        settings = {
            "entries": {
                "chain-entry": {
                    "title": "Chainload Entry",
                    "actions": ["act-chain"],
                },
                "print-entry": {
                    "title": "Print Entry",
                    "actions": ["act-print"],
                },
                "edera-entry": {
                    "title": "Edera Entry",
                    "actions": ["act-edera"],
                },
            },
            "actions": {
                "act-chain": {
                    "chainload": {
                        "path": r"\EFI\vmlinuz.efi",
                        "linux-initrd": r"\EFI\initrd.img",
                    },
                },
                "act-print": {
                    "print": {
                        "text": "Hello from Sprout Bootloader!",
                    },
                },
                "act-edera": {
                    "edera": {
                        "xen": r"\EFI\xen.efi",
                        "kernel": r"\EFI\vmlinuz.efi",
                        "kernel-options": ["console=tty0"],
                        "xen-options": ["dom0_mem=512M"],
                    },
                },
            },
        }

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers=self.drivers_config,
            settings=settings,
        )

        entry = self._create_sample_entry(mod)
        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ):
            mod.install_bootloader(self.temp_dir)

        config_path = self.esp_dir / mod.SPROUT_CONFIG
        data = tomllib.loads(config_path.read_text(encoding="utf-8"))

        act_chain = data["actions"]["act-chain"]["chainload"]
        self.assertEqual(act_chain["path"], r"\EFI\vmlinuz.efi")
        self.assertEqual(act_chain["linux-initrd"], r"\EFI\initrd.img")
        self.assertNotIn("linux-initrd-chain", act_chain)

        act_print = data["actions"]["act-print"]["print"]
        self.assertEqual(act_print["text"], "Hello from Sprout Bootloader!")

        act_edera = data["actions"]["act-edera"]["edera"]
        self.assertEqual(act_edera["xen"], r"\EFI\xen.efi")
        self.assertEqual(act_edera["kernel"], r"\EFI\vmlinuz.efi")
        self.assertEqual(act_edera["kernel-options"], ["console=tty0"])
        self.assertEqual(act_edera["xen-options"], ["dom0_mem=512M"])
        self.assertNotIn("initrd", act_edera)
        self.assertNotIn("initrd-chain", act_edera)

    def test_unknown_referenced_action_fails_before_publication(self) -> None:
        """Verify custom entry referencing unknown action fails before publication."""
        settings = {
            "entries": {
                "broken-entry": {
                    "title": "Broken",
                    "actions": ["missing-action"],
                },
            },
            "actions": {},
        }

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers=self.drivers_config,
            settings=settings,
        )

        entry = self._create_sample_entry(mod)
        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ):
            with self.assertRaises(RuntimeError) as ctx:
                mod.install_bootloader(self.temp_dir)
            self.assertIn("references unknown custom action 'missing-action'", str(ctx.exception))

        config_path = self.esp_dir / mod.SPROUT_CONFIG
        self.assertFalse(config_path.exists())

    def test_path_traversal_fails_before_publication(self) -> None:
        """Verify custom action path traversal escape fails before publication."""
        settings = {
            "entries": {
                "traversal-entry": {
                    "title": "Escape",
                    "actions": ["act-escape"],
                },
            },
            "actions": {
                "act-escape": {
                    "chainload": {
                        "path": r"..\..\etc\shadow",
                    },
                },
            },
        }

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers=self.drivers_config,
            settings=settings,
        )

        entry = self._create_sample_entry(mod)
        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ):
            with self.assertRaises(RuntimeError) as ctx:
                mod.install_bootloader(self.temp_dir)
            self.assertIn("references invalid kernel path", str(ctx.exception))

        config_path = self.esp_dir / mod.SPROUT_CONFIG
        self.assertFalse(config_path.exists())

    def test_unresolved_dynamic_variable_fails_before_publication(self) -> None:
        """Verify custom action with unresolved dynamic variable fails before publication."""
        settings = {
            "entries": {
                "unres-entry": {
                    "title": "Unresolved",
                    "actions": ["act-unres"],
                },
            },
            "actions": {
                "act-unres": {
                    "chainload": {
                        "path": r"\EFI\$missing_var\kernel.efi",
                    },
                },
            },
        }

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers=self.drivers_config,
            settings=settings,
        )

        entry = self._create_sample_entry(mod)
        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ):
            with self.assertRaises(RuntimeError) as ctx:
                mod.install_bootloader(self.temp_dir)
            self.assertIn("contains unresolved dynamic variable '$missing_var'", str(ctx.exception))

        config_path = self.esp_dir / mod.SPROUT_CONFIG
        self.assertFalse(config_path.exists())

    def test_missing_referenced_file_fails_before_publication(self) -> None:
        """Verify action referencing missing file on ESP fails before publication."""
        # Note: We do NOT create EFI/nonexistent.efi on the ESP
        settings = {
            "entries": {
                "missing-file-entry": {
                    "title": "Missing File",
                    "actions": ["act-missing"],
                },
            },
            "actions": {
                "act-missing": {
                    "chainload": {
                        "path": r"\EFI\nonexistent.efi",
                    },
                },
            },
        }

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers=self.drivers_config,
            settings=settings,
        )

        # Write a previous published configuration
        config_path = self.esp_dir / mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text("version = 1\n# previous-config\n")

        entry = self._create_sample_entry(mod)
        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ):
            with self.assertRaises(RuntimeError) as ctx:
                mod.install_bootloader(self.temp_dir)
            self.assertIn("references missing file", str(ctx.exception))

        # Previous config must be preserved
        self.assertEqual(config_path.read_text(), "version = 1\n# previous-config\n")

    def test_name_collision_preserves_previous_config_and_artifacts(self) -> None:
        """Verify generated NixOS entry name collision fails before publication and preserves previous config."""
        settings = {
            "entries": {
                "nixos-g1": {
                    "title": "Colliding Entry",
                    "actions": ["act-collide"],
                },
            },
            "actions": {
                "act-collide": {
                    "print": {"text": "hello"},
                },
            },
        }

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers=self.drivers_config,
            settings=settings,
        )

        config_path = self.esp_dir / mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text("version = 1\n# previous-valid-config\n")

        entry = self._create_sample_entry(mod, identifier="nixos-g1")
        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ):
            with self.assertRaises(RuntimeError) as ctx:
                mod.install_bootloader(self.temp_dir)
            self.assertTrue(
                "collides with generated NixOS entry" in str(ctx.exception)
                or "reserved 'nixos-' prefix" in str(ctx.exception)
            )

        self.assertEqual(config_path.read_text(), "version = 1\n# previous-valid-config\n")

    def test_gc_preserves_custom_referenced_files_in_managed_directory(self) -> None:
        """Verify garbage collection preserves custom-referenced files in managed directory and deletes stale artifacts."""
        custom_kernel = self.esp_dir / "EFI" / "Sprout" / "nixos" / "custom-kernel.efi"
        custom_kernel.parent.mkdir(parents=True, exist_ok=True)
        custom_kernel.write_text("custom-kernel-content")

        stale_file = self.esp_dir / "EFI" / "Sprout" / "nixos" / "stale-artifact.efi"
        stale_file.write_text("stale-artifact-content")

        settings = {
            "entries": {
                "custom-entry": {
                    "title": "Custom Managed",
                    "actions": ["act-custom"],
                },
            },
            "actions": {
                "act-custom": {
                    "chainload": {
                        "path": r"\EFI\Sprout\nixos\custom-kernel.efi",
                    },
                },
            },
        }

        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers=self.drivers_config,
            settings=settings,
        )

        entry = self._create_sample_entry(mod)
        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ):
            mod.install_bootloader(self.temp_dir)

        # Custom referenced file must STILL exist
        self.assertTrue(custom_kernel.is_file(), "Custom referenced file must be preserved by GC")
        # Stale unreferenced file must be removed
        self.assertFalse(stale_file.exists(), "Unreferenced stale artifact must be removed by GC")

    def test_empty_settings_preserves_existing_behavior(self) -> None:
        """Verify installation with empty settings preserves existing behavior without menu-style."""
        mod = load_sprout_installer(
            self.esp_dir,
            sprout_binary=self.sprout_source,
            drivers=self.drivers_config,
            settings={},
        )

        entry = self._create_sample_entry(mod)
        with patch.object(mod, "check_mountpoint"), patch.object(
            mod, "collect_entries", return_value=[entry]
        ):
            mod.install_bootloader(self.temp_dir)

        config_path = self.esp_dir / mod.SPROUT_CONFIG
        self.assertTrue(config_path.is_file())
        data = tomllib.loads(config_path.read_text(encoding="utf-8"))

        self.assertNotIn("menu-style", data["options"])
        self.assertEqual(data["options"]["default-entry"], "nixos-g1")
        self.assertIn("nixos-g1", data["entries"])
        self.assertIn("nixos-g1", data["actions"])
        self.assertEqual(len(data["entries"]), 1)
        self.assertEqual(len(data["actions"]), 1)


if __name__ == "__main__":
    unittest.main()

