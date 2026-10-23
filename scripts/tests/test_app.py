import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/lib/app.py"
spec = importlib.util.spec_from_file_location("app_config", SCRIPT)
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


class ConfigureAppTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / "Info.plist"
        self.source = (ROOT / "Resources/Info.plist").read_bytes()

    def configure(self, environment):
        self.path.write_bytes(self.source)
        app.configure_metadata(self.path, environment)
        return plistlib.loads(self.path.read_bytes())

    def test_local_and_ci_builds_keep_builtin_login_without_override(self):
        for environment in ({}, {"RURI_MICROSOFT_CLIENT_ID": ""}, {"RURI_MICROSOFT_CLIENT_ID": " \n"}):
            with self.subTest(environment=environment):
                info = self.configure(environment)
                self.assertEqual(info["RuriMicrosoftClientID"], plistlib.loads(self.source)["RuriMicrosoftClientID"])

    def test_distribution_can_override_client_id(self):
        client_id = "df01d133-3715-49b0-a48f-31e486c76402"
        info = self.configure({"RURI_MICROSOFT_CLIENT_ID": " " + client_id + "\n"})
        self.assertEqual(info["RuriMicrosoftClientID"], client_id)

    def test_package_managers_name_themselves(self):
        self.assertEqual(self.configure({"RURI_PACKAGE_MANAGER": "Nix\n"})["RuriPackageManager"], "Nix")
        for environment in ({}, {"RURI_PACKAGE_MANAGER": " "}):
            with self.subTest(environment=environment):
                self.assertNotIn("RuriPackageManager", self.configure(environment))

    def test_package_manager_must_be_a_short_name(self):
        with self.assertRaises(ValueError):
            self.configure({"RURI_PACKAGE_MANAGER": "<Nix>"})

    def test_invalid_override_does_not_silently_ship_a_broken_login(self):
        with self.assertRaises(ValueError):
            self.configure({"RURI_MICROSOFT_CLIENT_ID": "not-a-client-id"})
        self.assertEqual(self.path.read_bytes(), self.source)


class ConfigureComponentsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / "Info.plist"
        self.source = (ROOT / "Resources/Info.plist").read_bytes()
        self.path.write_bytes(self.source)

    def test_disabled_component_preserves_upstream_metadata_bytes(self):
        app.configure_components(self.path, {"RURI_ENABLE_VEX": "0"})
        self.assertEqual(self.path.read_bytes(), self.source)

    def test_enabled_component_registers_preview_links(self):
        for environment in ({}, {"RURI_ENABLE_VEX": "1"}):
            with self.subTest(environment=environment):
                app.configure_components(self.path, environment)
                info = plistlib.loads(self.path.read_bytes())
                self.assertEqual(info["CFBundleURLTypes"], [{
                    "CFBundleURLName": "dev.ruri.launcher.vex",
                    "CFBundleURLSchemes": ["ruri"],
                    "CFBundleTypeRole": "Viewer",
                }])
                del info["CFBundleURLTypes"]
                self.assertEqual(info, plistlib.loads(self.source))


class ConfigureUpdatesTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / "Info.plist"

    def configure(self, environment):
        self.path.write_bytes((ROOT / "Resources/Info.plist").read_bytes())
        app.configure_updates(self.path, environment)
        return plistlib.loads(self.path.read_bytes())

    def test_pinned_packages_keep_updates(self):
        pinned = hashlib.sha1((ROOT / "Resources/RuriSigning.cer").read_bytes()).hexdigest()
        info = self.configure({"RURI_SIGN_IDENTITY": pinned})
        self.assertIn("SUPublicEDKey", info)
        self.assertIn("RuriAppcastBaseURL", info)

    def test_ad_hoc_and_contributor_packages_never_update_to_official_releases(self):
        for environment in ({}, {"RURI_SIGN_IDENTITY": "-"}, {"RURI_SIGN_IDENTITY": "0123456789ABCDEF0123456789ABCDEF01234567"}):
            with self.subTest(environment=environment):
                info = self.configure(environment)
                self.assertNotIn("SUPublicEDKey", info)
                self.assertNotIn("RuriAppcastBaseURL", info)
                self.assertEqual(info["CFBundleIdentifier"], "dev.ruri.launcher")


class ConfigureServicesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.resources = self.root / "Ruri.app" / "Contents" / "Resources"
        self.local = self.root / ".private" / "curseforge-api-key"
        self.local.parent.mkdir()
        self.output = self.resources / "RuriServices.plist"

    def configure(self, environment=None):
        app.configure_services(self.resources, environment or {}, self.root)

    def bundled_key(self):
        return plistlib.loads(self.output.read_bytes())["CurseForgeAPIKey"]

    def test_local_key_is_literal_and_trimmed(self):
        self.local.write_text("  $2a$example&<>'\"+token\n")
        self.configure()
        self.assertEqual(self.bundled_key(), "$2a$example&<>'\"+token")

    def test_environment_wins_without_reading_local_file(self):
        self.local.write_bytes(b"\xff")
        self.configure({app.KEY_VARIABLE: "$ci-key"})
        self.assertEqual(self.bundled_key(), "$ci-key")

    def test_empty_environment_disables_local_key_and_removes_stale_resource(self):
        self.local.write_text("local-key")
        self.configure()
        self.configure({app.KEY_VARIABLE: ""})
        self.assertFalse(self.output.exists())

    def test_missing_and_empty_local_file_need_no_key(self):
        self.configure()
        self.assertFalse(self.output.exists())
        self.local.write_text(" \n")
        self.configure()
        self.assertFalse(self.output.exists())

    def test_invalid_keys_are_rejected_without_echoing_them(self):
        for key in ["key\ninjection", "key\rinjection", "key\x00", "key\ttoken", "key token", "密钥"]:
            with self.subTest(key=key):
                with self.assertRaises(ValueError) as error:
                    self.configure({app.KEY_VARIABLE: key})
                self.assertNotIn(key, str(error.exception))
                self.assertFalse(self.output.exists())

    def test_cli_never_prints_credentials_on_success_or_failure(self):
        self.resources.parent.mkdir(parents=True)
        source = app.ROOT / "Resources/Info.plist"
        (self.resources.parent / "Info.plist").write_bytes(source.read_bytes())
        for key, status in [("$example-key", 0), ("$example-key\ninjected", 1)]:
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "bundle", str(self.resources.parent.parent)],
                env={app.KEY_VARIABLE: key}, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, status)
            self.assertNotIn("$example-key", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
