from __future__ import annotations

import importlib.util
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType
from unittest.mock import patch


def load_sprout_installer(
    esp_mount: Path,
    sprout_binary: Path | None = None,
    drivers: dict[str, str] | None = None,
    timeout: int = 5,
    config_limit: int = 0,
    can_touch_efi: bool = False,
    removable: bool = False,
    entry_label: str = "NixOS Sprout",
) -> ModuleType:
    src_file = (
        Path(__file__).resolve().parent.parent
        / "modules"
        / "nixos"
        / "sprout-install.py"
    )
    code = src_file.read_text(encoding="utf-8")

    bin_path = sprout_binary or (esp_mount / "EFI" / "Sprout" / "sprout.efi")

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

    def test_driver_atomic_replacement(self) -> None:
        """Verify driver destination is replaced atomically without leaving stale files."""
        # 1. Existing driver destination has old contents
        dest = self.esp_dir / self.mod.DRIVERS_DIR / "btrfs.efi"
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text("driver-version-1")

        # 2. Update source file with new contents
        self.driver_src.write_text("driver-version-2")

        # 3. install_drivers replaces the file atomically
        installed = self.mod.install_drivers()

        self.assertIn("btrfs", installed)
        self.assertEqual(dest.read_text(), "driver-version-2")

        # Verify no temporary files remain
        tmp_files = list((self.esp_dir / self.mod.DRIVERS_DIR).glob("*.tmp"))
        self.assertEqual(tmp_files, [])

        # Verify nothing was written to working directory
        self.assertFalse((self.temp_dir / "EFI").exists())

    def test_stale_driver_cleaned_up_by_garbage_collection(self) -> None:
        """Verify stale drivers removed during garbage collection after publication."""
        dest_active = self.esp_dir / self.mod.DRIVERS_DIR / "btrfs.efi"
        dest_stale = self.esp_dir / self.mod.DRIVERS_DIR / "zfs.efi"
        dest_active.parent.mkdir(parents=True, exist_ok=True)

        dest_active.write_text("driver-btrfs")
        dest_stale.write_text("driver-zfs-stale")

        installed = self.mod.install_drivers()
        self.assertEqual(
            installed, {"btrfs": self.mod.DRIVERS_DIR / "btrfs.efi"}
        )

        # Run garbage collection on ESP
        self.mod.garbage_collect([], installed)

        self.assertTrue(
            dest_active.exists(), "Active configured driver must be kept"
        )
        self.assertFalse(
            dest_stale.exists(),
            "Stale unconfigured driver must be garbage collected",
        )
        self.assertFalse((self.temp_dir / "EFI").exists())

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
        config_path.write_text("pre-existing-valid-config")

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
            "pre-existing-valid-config",
            "Existing sprout.toml must remain untouched on failure",
        )

    def test_install_bootloader_all_entries_pruned_leaves_config_unchanged(
        self,
    ) -> None:
        """Verify that if all entries are pruned, the installer refuses publication and leaves existing configuration unchanged."""
        config_path = self.esp_dir / self.mod.SPROUT_CONFIG
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text("previous-published-sprout-configuration")

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
            "previous-published-sprout-configuration",
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
        config_path.write_text("pre-existing-config")

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

        self.assertEqual(config_path.read_text(), "pre-existing-config")
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
        self.assertTrue(
            (self.esp_dir / self.mod.DRIVERS_DIR / "btrfs.efi").exists()
        )

        # CWD must contain NO boot artifacts / directories
        self.assertFalse((self.temp_dir / "EFI").exists())
        self.assertFalse((self.temp_dir / "sprout.toml").exists())
        self.assertFalse((self.temp_dir / entry.kernel).exists())
        self.assertFalse((self.temp_dir / entry.initrds[0]).exists())



if __name__ == "__main__":
    unittest.main()
