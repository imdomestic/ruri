import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import sys
import uuid
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.localization import shipping_languages

ROOT = Path(__file__).resolve().parents[2]
KEY_VARIABLE = "RURI_CURSEFORGE_API_KEY"


def configure_metadata(path: Path, environment=None) -> None:
    environment = os.environ if environment is None else environment
    with path.open("rb") as source:
        info = plistlib.load(source)
    info["CFBundleDevelopmentRegion"] = "zh-Hans"
    info["CFBundleLocalizations"] = shipping_languages(ROOT)
    version = environment.get("RURI_VERSION") or info.get("RuriVersion") or info["CFBundleShortVersionString"]
    number = r"(?:0|[1-9][0-9]*)"
    identifier = r"(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
    match = re.fullmatch(rf"({number}\.{number}\.{number})(?:-{identifier}(?:\.{identifier})*)?", version)
    if not match:
        raise ValueError("RURI_VERSION must be X.Y.Z or X.Y.Z-prerelease (without a v prefix).")
    build_number = environment.get("RURI_BUILD_NUMBER") or info["CFBundleVersion"]
    if not re.fullmatch(r"[1-9][0-9]*", build_number):
        raise ValueError("RURI_BUILD_NUMBER must be a positive integer.")
    client_id = environment.get("RURI_MICROSOFT_CLIENT_ID", "").strip() or info.get("RuriMicrosoftClientID", "").strip()
    if client_id:
        # Canonical UUIDs only; a client ID is public, not a client secret.
        if str(uuid.UUID(client_id)) != client_id.lower():
            raise ValueError("RURI_MICROSOFT_CLIENT_ID must be a UUID.")
        info["RuriMicrosoftClientID"] = client_id
    else:
        info.pop("RuriMicrosoftClientID", None)
    # Package managers that put ruri on PATH themselves, such as Nix, name
    # themselves so the app and CLI do not offer their own command-line link.
    package_manager = environment.get("RURI_PACKAGE_MANAGER", "").strip()
    if package_manager:
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 .+-]{0,31}", package_manager):
            raise ValueError("RURI_PACKAGE_MANAGER must be a short name such as Nix.")
        info["RuriPackageManager"] = package_manager
    else:
        info.pop("RuriPackageManager", None)
    info["CFBundleShortVersionString"] = match[1]
    info["CFBundleVersion"] = build_number
    info["RuriVersion"] = version
    with path.open("wb") as destination:
        plistlib.dump(info, destination, sort_keys=False)


def configure_components(path: Path, environment=None) -> None:
    environment = os.environ if environment is None else environment
    if environment.get("RURI_ENABLE_VEX") == "0":
        return
    with path.open("rb") as source:
        info = plistlib.load(source)
    info["CFBundleURLTypes"] = [{
        "CFBundleURLName": "dev.ruri.launcher.vex",
        "CFBundleURLSchemes": ["ruri"],
        "CFBundleTypeRole": "Viewer",
    }]
    with path.open("wb") as destination:
        plistlib.dump(info, destination, sort_keys=False)



def configure_updates(path: Path, environment=None) -> None:
    environment = os.environ if environment is None else environment
    # Official releases verify against the pinned identity. An ad hoc or
    # contributor-signed package is a local or fork build: Sparkle would accept
    # a signed official release over it, so it ships without an update key or feed.
    identity = environment.get("RURI_SIGN_IDENTITY", "-").upper()
    if identity != "-" and identity == hashlib.sha1((ROOT / "Resources/RuriSigning.cer").read_bytes()).hexdigest().upper():
        return
    with path.open("rb") as source:
        info = plistlib.load(source)
    for key in ("SUPublicEDKey", "RuriAppcastBaseURL"):
        info.pop(key, None)
    with path.open("wb") as destination:
        plistlib.dump(info, destination, sort_keys=False)


def configure_services(resources: Path, environment=None, root: Path = ROOT) -> None:
    environment = os.environ if environment is None else environment
    # Read raw text, never source a shell file: CurseForge keys can contain '$'.
    # An explicitly empty environment value disables local-file fallback.
    if KEY_VARIABLE in environment:
        key = environment[KEY_VARIABLE]
    else:
        local = root / ".private" / "curseforge-api-key"
        key = local.read_text(encoding="utf-8") if local.exists() else ""
    key = key.strip()
    if any(not 0x21 <= ord(character) <= 0x7E for character in key):
        raise ValueError("CurseForge API key must be a single printable ASCII token.")
    destination = resources / "RuriServices.plist"
    if not key:
        destination.unlink(missing_ok=True)
        return
    resources.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(plistlib.dumps({"CurseForgeAPIKey": key}))



if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Configure application metadata and bundled services before signing.")
    parser.add_argument("action", choices=["metadata", "bundle"])
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    try:
        if args.action == "metadata":
            configure_metadata(args.path)
        else:
            configure_metadata(args.path / "Contents/Info.plist")
            configure_updates(args.path / "Contents/Info.plist")
            configure_components(args.path / "Contents/Info.plist")
            configure_services(args.path / "Contents/Resources")
    except (ValueError, OSError) as error:
        # Service credentials must never be included in command output.
        if args.action == "metadata":
            sys.exit(f"Invalid application metadata: {error}")
        sys.exit("Unable to configure application metadata or service credentials.")
