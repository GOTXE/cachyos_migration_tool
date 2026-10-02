import importlib.util
import os
import subprocess
import tempfile
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
spec = importlib.util.spec_from_file_location("tui", os.path.join(ROOT, "src", "lib", "tui.py"))
tui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tui)


def write(path, content=""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        handle.write(content)


def make_v2(path, created, host):
    write(os.path.join(path, "metadata", "manifest.env"),
          f"FORMAT_VERSION=2\nCREATED_AT={created}\nHOST_LABEL={host}\n")


class BackupDiscovery(unittest.TestCase):
    def test_is_backup_dir_accepts_v2_and_v1(self):
        with tempfile.TemporaryDirectory() as tmp:
            v2 = os.path.join(tmp, "v2")
            v1 = os.path.join(tmp, "v1")
            empty = os.path.join(tmp, "empty")
            make_v2(v2, "2026-01-01T10:00:00+0000", "h")
            write(os.path.join(v1, "metadata", "user_ids.conf"), "UID=1\n")
            os.makedirs(empty)
            self.assertTrue(tui._is_backup_dir(v2))
            self.assertTrue(tui._is_backup_dir(v1))
            self.assertFalse(tui._is_backup_dir(empty))

    def test_sort_by_created_at_not_by_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            newest = os.path.join(tmp, "aaa_05_09_2026-10:00")
            oldest = os.path.join(tmp, "zzz_01_01_2026-10:00")
            legacy = os.path.join(tmp, "mmm_v1")
            make_v2(newest, "2026-09-05T10:00:00+0000", "aaa")
            make_v2(oldest, "2026-01-01T10:00:00+0000", "zzz")
            write(os.path.join(legacy, "metadata", "user_ids.conf"), "UID=1\n")
            os.utime(os.path.join(legacy, "metadata", "user_ids.conf"), (1777629600, 1777629600))  # 2026-05-01
            ordered = tui._sort_backups([oldest, legacy, newest])
            self.assertEqual(ordered, [newest, legacy, oldest])

    def test_backup_host_label(self):
        with tempfile.TemporaryDirectory() as tmp:
            v2 = os.path.join(tmp, "v2")
            make_v2(v2, "2026-01-01T10:00:00+0000", "mbp-gotxe")
            self.assertEqual(tui._backup_host_label(v2), "mbp-gotxe")
            self.assertEqual(tui._backup_host_label(os.path.join(tmp, "nada")), "")


class ExtractDestination(unittest.TestCase):
    def test_prefers_destino_line(self):
        lines = ["Destino:", "/mnt/disk/pc_02_10_2026-14:30", ""]
        self.assertEqual(tui._extract_backup_destination(lines), "/mnt/disk/pc_02_10_2026-14:30")

    def test_fallback_accepts_v1_and_v2_names(self):
        self.assertEqual(
            tui._extract_backup_destination(["x", "/mnt/d/linux_backup_2026-10-02_14-30-05"]),
            "/mnt/d/linux_backup_2026-10-02_14-30-05")
        self.assertEqual(
            tui._extract_backup_destination(["x", "/mnt/d/mi-pc_02_10_2026-14:30"]),
            "/mnt/d/mi-pc_02_10_2026-14:30")
        self.assertEqual(
            tui._extract_backup_destination(["x", "/mnt/d/mi-pc_02_10_2026-14h30_2"]),
            "/mnt/d/mi-pc_02_10_2026-14h30_2")
        self.assertIsNone(tui._extract_backup_destination(["x", "/mnt/d/otra-cosa"]))


class VerifyV2(unittest.TestCase):
    def test_verify_uses_v2_layout(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = os.path.join(tmp, "home")
            ext = os.path.join(tmp, "ext", "data1")
            backup = os.path.join(tmp, "backup")
            write(os.path.join(home, ".config", "Code", "User", "settings.json"), "{}\n")
            write(os.path.join(home, "Documents", "notes.txt"), "n\n")
            write(os.path.join(ext, "f.txt"), "f\n")
            # backup v2 equivalente
            write(os.path.join(backup, "configs", ".config", "Code", "User", "settings.json"), "{}\n")
            write(os.path.join(backup, "data", "home", "Documents", "notes.txt"), "n\n")
            write(os.path.join(backup, "data", "external", ext.lstrip(os.sep), "f.txt"), "f\n")
            make_v2(backup, "2026-01-01T10:00:00+0000", "h")

            result = tui._verify_backup_selection(
                backup, home, [".config/Code"], [os.path.join(home, "Documents"), ext])
            self.assertEqual(result["status"], "ok", result)
            self.assertEqual(result["missing"], [])
            self.assertEqual(result["mismatched"], [])

            # una configuración anidada que falta en el backup se detecta
            os.remove(os.path.join(backup, "configs", ".config", "Code", "User", "settings.json"))
            result = tui._verify_backup_selection(
                backup, home, [".config/Code"], [os.path.join(home, "Documents"), ext])
            self.assertNotEqual(result["status"], "ok")
            self.assertTrue(any("settings.json" in item for item in result["missing"]), result)


if __name__ == "__main__":
    unittest.main()
