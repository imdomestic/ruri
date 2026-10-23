#!/usr/bin/env python3
"""Sign release DMGs for Sparkle and build the per-architecture appcasts.

sign:    run after scripts/package-dmg.sh. Reads the EdDSA private key from
         RURI_SPARKLE_PRIVATE_KEY, checks the signature against the public key
         embedded in the app and writes <dmg>.sparkle.json next to the DMG.
appcast: collects published GitHub releases that carry those metadata assets
         and writes appcast-<arch>.xml files. Needs only the gh CLI.
"""

import argparse
from email.utils import format_datetime
from datetime import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ElementTree

ROOT = Path(__file__).resolve().parents[2]
ARCHITECTURES = ("arm64", "x86_64")
PRERELEASE_CHANNEL = "prerelease"
ITEM_LIMIT = 10
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DMG = re.compile(r"Ruri-(.+)-macOS-(arm64|x86_64)\.dmg")

VERIFY_SWIFT = """
import CryptoKit
import Foundation
let arguments = CommandLine.arguments
guard let key = Data(base64Encoded: arguments[1]), let signature = Data(base64Encoded: arguments[2]) else { exit(2) }
let data = try Data(contentsOf: URL(fileURLWithPath: arguments[3]), options: .alwaysMapped)
exit(try Curve25519.Signing.PublicKey(rawRepresentation: key).isValidSignature(signature, for: data) ? 0 : 1)
"""


class UpdateError(Exception):
    pass


def sign(app, dmg):
    key = os.environ.get("RURI_SPARKLE_PRIVATE_KEY", "").strip()
    if not key:
        raise UpdateError("RURI_SPARKLE_PRIVATE_KEY is not set.")
    match = DMG.fullmatch(dmg.name)
    if not match:
        raise UpdateError(f"Unexpected DMG name: {dmg.name}")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("RuriVersion") != match[1]:
        raise UpdateError(f"{dmg.name} does not match the built app version {info.get('RuriVersion')}.")
    # 与 scripts/swift-build.sh 使用相同的组件、架构和配置目录。
    component = "without-vex" if os.environ.get("RURI_ENABLE_VEX") == "0" else "with-vex"
    build_dir = Path(os.environ.get("RURI_BUILD_DIR", ".build")) / component / os.environ.get("RURI_ARCH", "") / "release-scratch"
    tool = (build_dir if build_dir.is_absolute() else ROOT / build_dir) / "artifacts/sparkle/Sparkle/bin/sign_update"
    if not tool.is_file():
        raise UpdateError(f"Sparkle sign_update was not found at {tool}.")
    # The key only travels on stdin; never place it in argv or output.
    environment = {name: value for name, value in os.environ.items() if name != "RURI_SPARKLE_PRIVATE_KEY"}
    result = subprocess.run([str(tool), "--ed-key-file", "-", "-p", str(dmg)], input=key + "\n",
                            capture_output=True, text=True, env=environment)
    if result.returncode:
        raise UpdateError(f"sign_update failed (exit {result.returncode}).")
    signature = result.stdout.strip()
    # Updates signed by a key other than the embedded one would never install.
    with tempfile.TemporaryDirectory(prefix="ruri-sparkle-") as directory:
        script = Path(directory) / "verify.swift"
        script.write_text(VERIFY_SWIFT)
        verified = subprocess.run(["xcrun", "swift", str(script), info["SUPublicEDKey"], signature, str(dmg)],
                                  capture_output=True, env=environment)
    if verified.returncode:
        raise UpdateError("The update signature does not match SUPublicEDKey in the app.")
    metadata = {
        "file": dmg.name,
        "version": info["CFBundleVersion"],
        "shortVersion": info["RuriVersion"],
        "minimumSystemVersion": info["LSMinimumSystemVersion"],
        "edSignature": signature,
        "length": dmg.stat().st_size,
    }
    output = dmg.with_name(dmg.name + ".sparkle.json")
    output.write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Signed {dmg.name} for Sparkle (build {metadata['version']}).")


def gh(*arguments, binary=False):
    result = subprocess.run(["gh", *arguments], capture_output=True, check=True)
    return result.stdout if binary else result.stdout.decode()


def releases(repository):
    pages = json.loads(gh("api", "--paginate", "--slurp", f"repos/{repository}/releases"))
    return [release for page in pages for release in page if not release["draft"]]


def item(release, dmg, metadata):
    element = ElementTree.Element("item")
    def child(name, text, **attributes):
        node = ElementTree.SubElement(element, name, attributes)
        node.text = text
        return node
    child("title", release["name"] or release["tag_name"])
    published = datetime.fromisoformat(release["published_at"].replace("Z", "+00:00"))
    child("pubDate", format_datetime(published))
    child("link", release["html_url"])
    child(f"{{{SPARKLE}}}version", metadata["version"])
    child(f"{{{SPARKLE}}}shortVersionString", metadata["shortVersion"])
    child(f"{{{SPARKLE}}}minimumSystemVersion", metadata["minimumSystemVersion"])
    if release["prerelease"]:
        child(f"{{{SPARKLE}}}channel", PRERELEASE_CHANNEL)
    child(f"{{{SPARKLE}}}fullReleaseNotesLink", release["html_url"])
    if (release.get("body") or "").strip():
        child("description", release["body"], **{f"{{{SPARKLE}}}format": "markdown"})
    child("enclosure", None, url=dmg["browser_download_url"], length=str(dmg["size"]),
          type="application/octet-stream", **{f"{{{SPARKLE}}}edSignature": metadata["edSignature"]})
    return element


def appcast(repository, output):
    feeds = {architecture: [] for architecture in ARCHITECTURES}
    for release in releases(repository):
        assets = {asset["name"]: asset for asset in release["assets"]}
        for name, dmg in assets.items():
            match = DMG.fullmatch(name)
            metadata_asset = assets.get(name + ".sparkle.json")
            if not match or not metadata_asset:
                continue
            metadata = json.loads(gh("api", "-H", "Accept: application/octet-stream",
                                     f"repos/{repository}/releases/assets/{metadata_asset['id']}", binary=True))
            if metadata.get("file") != name or metadata.get("length") != dmg["size"]:
                raise UpdateError(f"Sparkle metadata for {name} in {release['tag_name']} does not match the DMG.")
            feeds[match[2]].append((int(metadata["version"]), item(release, dmg, metadata)))
    ElementTree.register_namespace("sparkle", SPARKLE)
    output.mkdir(parents=True, exist_ok=True)
    for architecture, items in feeds.items():
        rss = ElementTree.Element("rss", version="2.0")
        channel = ElementTree.SubElement(rss, "channel")
        ElementTree.SubElement(channel, "title").text = f"Ruri ({architecture})"
        ElementTree.SubElement(channel, "link").text = f"https://github.com/{repository}/releases"
        for _, element in sorted(items, key=lambda entry: entry[0], reverse=True)[:ITEM_LIMIT]:
            channel.append(element)
        ElementTree.indent(rss)
        path = output / f"appcast-{architecture}.xml"
        ElementTree.ElementTree(rss).write(path, encoding="utf-8", xml_declaration=True)
        print(f"Wrote {path} with {min(len(items), ITEM_LIMIT)} item(s).")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    signing = commands.add_parser("sign")
    signing.add_argument("app", type=Path)
    signing.add_argument("dmgs", type=Path, nargs="+")
    feed = commands.add_parser("appcast")
    feed.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"), required="GITHUB_REPOSITORY" not in os.environ)
    feed.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "sign":
        for dmg in args.dmgs:
            sign(args.app, dmg)
    else:
        appcast(args.repository, args.output)


if __name__ == "__main__":
    try:
        main()
    except (UpdateError, subprocess.CalledProcessError) as error:
        sys.exit(f"Sparkle update: {error}")
