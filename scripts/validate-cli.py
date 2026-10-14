#!/usr/bin/env python3
"""Exercise the distributed CLI using only disposable data and installation paths."""
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile


def command(arguments, **kwargs):
    result = subprocess.run(list(map(str, arguments)), capture_output=True, timeout=45, **kwargs)
    if result.returncode:
        raise RuntimeError(f"CLI package check failed ({result.returncode}): {result.stderr.decode(errors='replace')[:1000]}")
    return result.stdout


def designated_requirement(path):
    result = subprocess.run(["codesign", "-d", "-r-", str(path)], capture_output=True, check=True)
    for line in (result.stdout + result.stderr).decode().splitlines():
        if line.startswith("designated => "):
            return line
    raise RuntimeError("Missing designated requirement")


def validate(app):
    app = app.resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    executable = app / "Contents/Helpers/ruri-cli"
    details = subprocess.run(["codesign", "-d", "--verbose=2", str(app)], capture_output=True, check=True)
    if b"TeamIdentifier=not set" not in details.stderr:
        if designated_requirement(app) != designated_requirement(executable):
            raise RuntimeError("GUI and CLI must share a designated requirement for existing Keychain entries")
    with tempfile.TemporaryDirectory(prefix="ruri cli package ") as temporary:
        root = Path(temporary)
        data = root / "data directory"
        environment = dict(os.environ, RURI_DATA_DIR=str(root / "wrong data directory"), RURI_LANGUAGE="zh-Hans")
        Path(environment["RURI_DATA_DIR"]).mkdir()
        (Path(environment["RURI_DATA_DIR"]) / "state.json").write_text("invalid")

        def invoke(binary, *arguments, input=None):
            result = json.loads(command([binary, *arguments, "--data-dir", data, "--json", "--quiet"], env=environment, input=input))
            assert result["schemaVersion"] == 1 and result["ok"] and result["error"] is None, result
            return result["data"]

        assert command([executable, "--version"], env=environment).decode().strip() == info.get("RuriVersion", info["CFBundleShortVersionString"])
        for arguments, usage in [
            (["--help"], "USAGE: ruri-chorus <subcommand>"),
            (["--help", "app"], "USAGE: ruri-chorus app <subcommand>"),
            (["app", "--help"], "USAGE: ruri-chorus app <subcommand>"),
            (["help", "app"], "USAGE: ruri-chorus app <subcommand>"),
            (["app"], "USAGE: ruri-chorus app <subcommand>"),
        ]:
            help_text = command([executable, *arguments], env=environment).decode()
            assert usage in help_text and "USAGE: help " not in help_text, help_text
        grouped = command([executable, "help", "instance"], env=environment).decode()
        assert "ruri-chorus instance component set <id>" in grouped and "--component" in grouped
        assert not re.search(r"[\u3400-\u9fff]", grouped), "CLI help must default to English"
        chinese = command([executable, "help", "instance", "--language", "zh-Hans"], env=environment).decode()
        assert re.search(r"[\u3400-\u9fff]", chinese), "Explicit zh-Hans help must contain Chinese"
        catalog_path = Path(__file__).resolve().parents[1] / "Sources/RuriLocalization/Resources/CLIInterface.xcstrings"
        catalog = json.loads(catalog_path.read_text())
        expected = catalog["strings"]["CLIInterface.instanceListHelp"]["localizations"]["zh-Hans"]["stringUnit"]["value"]
        assert expected in chinese, chinese
        complete = command([executable, "help", "--all"], env=environment)
        assert len(complete) < 35_000
        index = invoke(executable, "schema")
        assert len(json.dumps(index).encode()) < 40_000
        assert "patchSchemas" not in index
        for item in index["commands"]:
            assert item["usage"] in complete.decode()
            assert "inputSchema" not in item and "resultSchema" not in item
        leaf = invoke(executable, "schema", "instance", "list")
        assert len(json.dumps(leaf).encode()) < 5_000
        assert set(leaf) == {"commands"}
        patch = invoke(executable, "schema", "config", "apply", "--input", "--scope", "instance")
        assert set(patch["patchSchemas"]) == {"instance"}
        assert "resultSchema" not in patch["commands"][0]
        assert not data.exists(), "Discovery must not create a state directory"
        invoke(executable, "config", "apply", "--scope", "app", "--file", "-", input=b'{"set":{"concurrentDownloads":7}}')
        assert invoke(executable, "config", "get", "--scope", "app")["effective"]["concurrentDownloads"] == 7
        created = invoke(executable, "instance", "create", "--name", "Package fixture", "--game", "1.21.1", "--directory", "default", "--no-install")
        assert invoke(executable, "instance", "show", created["instance"]["id"])["name"] == "Package fixture"

        # Default text must be independently usable; JSON/NDJSON retain their contract.
        readable = command([executable, "instance", "list", "--data-dir", data], env=environment).decode()
        assert created["instance"]["id"] in readable and "Package fixture" in readable
        assert not readable.lstrip().startswith("{")
        original_state = (data / "state.json").read_bytes()
        preview = command([executable, "config", "set", "concurrentDownloads", "9", "--scope", "app",
                           "--dry-run", "--data-dir", data], env=environment).decode()
        assert "7 → 9" in preview and "revision:" in preview
        assert "before" not in preview and "after" not in preview
        assert "Preview: configuration changes" in preview
        assert not re.search(r"[\u3400-\u9fff]", preview)
        assert (data / "state.json").read_bytes() == original_state
        current = command([executable, "config", "get", "concurrentDownloads", "--scope", "app",
                           "--data-dir", data], env=environment).decode()
        assert "concurrentDownloads" in current and "7" in current and "source" in current
        events = command([executable, "app", "info", "--output", "ndjson", "--data-dir", data], env=environment).splitlines()
        assert len(events) == 1 and json.loads(events[0])["type"] == "result"
        bad = subprocess.run([executable, "unknown-command"], env=environment, capture_output=True, timeout=45)
        assert bad.returncode == 2 and not bad.stdout and b"INVALID_ARGUMENT" in bad.stderr

        copied = root / "App with spaces" / "Ruri.app"
        copied.parent.mkdir()
        # ditto preserves bundle symlinks, executable modes and signatures.
        command(["ditto", app, copied])
        bundled = copied / "Contents/Helpers/ruri-cli"
        bin_dir = root / "user bin"
        assert invoke(bundled, "cli", "install", "--bin-dir", bin_dir)["status"]["installed"]
        # CHORUS: 验证独立命令链接。
        link = bin_dir / "ruri-chorus"
        assert Path(invoke(link, "app", "info")["application"]).resolve() == copied.resolve()
        command([link, "--localization-check"])
        assert "USAGE: ruri-chorus app <subcommand>" in command([link, "--help", "app"], env=environment).decode()
        moved = root / "Moved Ruri.app"
        shutil.move(copied, moved)
        relocated = moved / "Contents/Helpers/ruri-cli"
        assert not invoke(relocated, "cli", "status", "--bin-dir", bin_dir)["installed"]
        assert invoke(relocated, "cli", "install", "--bin-dir", bin_dir)["status"]["installed"]
        assert Path(invoke(link, "app", "info")["application"]).resolve() == moved.resolve()
        # Check helpers with fresh data so doctor needs no Java installation,
        # network access, credentials, or game download.
        clean_data = root / "doctor data"
        result = json.loads(command([link, "doctor", "--data-dir", clean_data, "--json"], env=environment))
        assert result["ok"] and result["data"]["healthy"], result
        assert invoke(link, "cli", "uninstall", "--bin-dir", bin_dir, "--yes")["changed"]
        assert not link.is_symlink()
    print("CLI: discovery budgets, text/JSON/NDJSON, stdin, configuration, helpers, relocation and link repair verified")


if __name__ == "__main__":
    validate(Path(sys.argv[1]))
