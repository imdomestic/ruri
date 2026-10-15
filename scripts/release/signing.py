import argparse
import base64
from contextlib import contextmanager
import hashlib
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CERTIFICATE = ROOT / "Resources/RuriSigning.cer"
INTERMEDIATE_CERTIFICATE = ROOT / "Resources/AppleWWDRCAG3.cer"
SECRET_VARIABLES = ("RURI_SIGN_P12_BASE64", "RURI_SIGN_P12_PASSWORD")


class SigningError(Exception):
    pass


def command(arguments, *, label, env=None, include_stderr=False):
    environment = dict(os.environ if env is None else env)
    for name in SECRET_VARIABLES:
        environment.pop(name, None)
    input_data = None
    if arguments[0] == "security":
        # security supports one command on stdin in interactive mode and
        # returns that command's status at EOF. Keep passwords out of argv.
        values = arguments[1:]
        if len(values) > 32 or any(any(c in value for c in "\0\r\n") for value in values):
            raise SigningError(f"{label} has invalid input.")
        def quote(value):
            return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
        input_data = (" ".join(map(quote, values)) + "\n").encode()
        if len(input_data) >= 4096:
            raise SigningError(f"{label} input is too long.")
        arguments = ["/usr/bin/security", "-i"]
    result = subprocess.run(arguments, input=input_data, capture_output=True, env=environment)
    if result.returncode:
        # security/openssl arguments can contain passwords. Never include the
        # command line, environment or captured output in an exception/log.
        raise SigningError(f"{label} failed (exit {result.returncode}).")
    return result.stdout + (result.stderr if include_stderr else b"")


def fingerprint():
    if not CERTIFICATE.is_file():
        raise SigningError("The public Ruri signing certificate is missing.")
    return hashlib.sha1(CERTIFICATE.read_bytes()).hexdigest().upper()


def certificate_team():
    subject = command(["/usr/bin/openssl", "x509", "-inform", "DER", "-in", str(CERTIFICATE),
                       "-noout", "-subject", "-nameopt", "RFC2253"], label="Certificate team lookup").decode()
    match = re.search(r"(?:^|,)OU=([A-Z0-9]{10})(?:,|$)", subject.strip())
    if not match:
        raise SigningError("The pinned signing certificate has no Apple Team ID.")
    return match[1]


def available_identities(keychain=None):
    arguments = ["security", "find-identity", "-v", "-p", "codesigning"]
    if keychain is not None:
        arguments.append(str(keychain))
    output = command(arguments, label="Signing identity lookup").decode()
    return {value.upper() for value in re.findall(r'^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"', output, re.MULTILINE)}


def save_private(path, data):
    with path.open("xb") as output:
        os.chmod(path, 0o600)
        output.write(data)


def signing_material(environment):
    encoded = environment.get(SECRET_VARIABLES[0], "")
    password = environment.get(SECRET_VARIABLES[1], "")
    if encoded or password:
        if not encoded or not password:
            raise SigningError("Both signing certificate and password secrets are required.")
        try:
            data = base64.b64decode(encoded, validate=True)
        except ValueError:
            raise SigningError("The signing certificate secret is not valid Base64.") from None
        if not data or len(data) > 65536:
            raise SigningError("The signing certificate secret has an invalid size.")
        return data, password
    # 本机构建使用钥匙串中已有的 Apple Development 身份。
    return None


@contextmanager
def signing_environment(environment):
    child = dict(environment)
    for name in SECRET_VARIABLES:
        child.pop(name, None)
    child.pop("RURI_SIGN_KEYCHAIN", None)
    child["RURI_SIGNING_ACTIVE"] = "1"
    override = environment.get("RURI_SIGN_IDENTITY")
    identity = fingerprint()
    if override and override != "-" and override.upper() != identity:
        raise SigningError("The requested signing identity does not match the pinned Apple certificate.")
    if override == "-":
        raise SigningError("Ruri Chorus requires its pinned Apple Development identity.")
    material = signing_material(environment)
    if material is None:
        if not (environment.get("CI") or environment.get("GITHUB_ACTIONS")) and identity in available_identities():
            child["RURI_SIGN_IDENTITY"] = identity
            print(f"Signing with the local Apple Development identity: {identity}", flush=True)
            yield child
            return
        raise SigningError("The pinned Apple Development identity is unavailable. Supply signing secrets in CI or install it with Xcode locally.")
    keychain_password = secrets.token_urlsafe(48)
    with tempfile.TemporaryDirectory(prefix="ruri-signing-", dir=environment.get("RUNNER_TEMP")) as temporary:
        work = Path(temporary)
        keychain = work / "signing.keychain-db"
        p12 = work / "identity.p12"
        save_private(p12, material[0])
        try:
            command(["security", "create-keychain", "-p", keychain_password, str(keychain)], label="Temporary keychain creation")
            command(["security", "set-keychain-settings", "-lut", "21600", str(keychain)], label="Keychain settings")
            command(["security", "unlock-keychain", "-p", keychain_password, str(keychain)], label="Keychain unlock")
            # codesign --keychain selects the identity, but its certificate
            # chain is resolved through the user's search list. Preserve all
            # existing entries; delete-keychain removes our entry on cleanup.
            search_list = shlex.split(command(["security", "list-keychains", "-d", "user"],
                                             label="Keychain search list lookup").decode())
            if str(keychain) not in search_list:
                command(["security", "list-keychains", "-d", "user", "-s", *search_list, str(keychain)],
                        label="Temporary keychain search configuration")
            # Hosted runners need not have the WWDR intermediate preinstalled.
            # Import its public certificate without changing any trust settings.
            command(["security", "import", str(INTERMEDIATE_CERTIFICATE), "-k", str(keychain)],
                    label="Apple intermediate certificate import")
            command(["security", "import", str(p12), "-k", str(keychain), "-f", "pkcs12", "-P", material[1],
                     "-x", "-T", "/usr/bin/codesign"], label="Signing identity import")
            command(["security", "set-key-partition-list", "-S", "apple-tool:", "-s", "-k", keychain_password, str(keychain)],
                    label="Signing key access configuration")
            if identity not in available_identities(keychain):
                raise SigningError("The private signing identity does not match the public Ruri certificate.")
            p12.unlink()
            child["RURI_SIGN_IDENTITY"] = identity
            child["RURI_SIGN_KEYCHAIN"] = str(keychain)
            print(f"Signing with the pinned Apple Development identity: {identity}", flush=True)
            yield child
        finally:
            if keychain.exists():
                command(["security", "delete-keychain", str(keychain)], label="Temporary signing keychain cleanup")


def verify(app, environment):
    identity = environment.get("RURI_SIGN_IDENTITY", "")
    if identity.upper() != fingerprint():
        raise SigningError("A signed package must use the pinned Apple Development certificate.")
    team = certificate_team()
    # 核验 Apple 证书及 Team ID，使重新构建继续使用同一钥匙串身份。
    requirement = (f'anchor apple generic and certificate leaf = H"{identity}" '
                   'and certificate 1[field.1.2.840.113635.100.6.2.1] exists '
                   'and certificate leaf[field.1.2.840.113635.100.6.1.12] exists '
                   f'and certificate leaf[subject.OU] = "{team}"')
    # CHORUS: 核验独立应用实际包含的辅助程序。
    targets = [app, app / "Contents/Helpers/ruri-cli", app / "Contents/Helpers/ruri-monitor", app / "Contents/Helpers/RuriGame.app",
               app / "Contents/Helpers/RuriGame.app/Contents/Frameworks/libRuriGameSupport.dylib"]
    for target in targets:
        command(["codesign", "--verify", "--all-architectures", "--strict", "-R",
                 "=" + requirement, str(target)], label=f"Signature verification for {target.name}")
        details = command(["codesign", "-d", "--verbose=2", str(target)],
                          label=f"Signing team verification for {target.name}", include_stderr=True).decode()
        if f"TeamIdentifier={team}" not in details.splitlines():
            raise SigningError(f"The signing Team ID for {target.name} does not match the pinned certificate.")
    launcher_requirement = requirement + ' and identifier "dev.ruri.launcher.chorus"'
    designated = []
    for target in (app, app / "Contents/Helpers/ruri-cli"):
        command(["codesign", "--verify", "--strict", "-R", "=" + launcher_requirement, str(target)],
                label=f"Launcher identity verification for {target.name}")
        output = command(["codesign", "-d", "-r-", str(target)],
                         label=f"Designated requirement lookup for {target.name}", include_stderr=True).decode()
        lines = [line for line in output.splitlines() if line.startswith("designated => ")]
        if len(lines) != 1:
            raise SigningError(f"The designated requirement for {target.name} is unavailable.")
        designated.append(lines[0])
    if designated[0] != designated[1]:
        raise SigningError("Ruri Chorus and its CLI must have the same designated requirement.")
    print(f"Verified the Apple certificate and Team ID {team} on the app and every helper.")


def cleanup_ci(environment):
    runner_temp = environment.get("RUNNER_TEMP")
    if not runner_temp:
        raise SigningError("CI cleanup requires RUNNER_TEMP.")
    for work in Path(runner_temp).glob("ruri-signing-*"):
        if not work.is_dir() or work.is_symlink():
            continue
        keychain = work / "signing.keychain-db"
        if keychain.exists():
            command(["security", "delete-keychain", str(keychain)], label="Leftover signing keychain cleanup")
        shutil.rmtree(work)


def run_build(arguments, environment):
    process = subprocess.Popen(arguments, env=environment, start_new_session=True)
    try:
        return process.wait()
    except KeyboardInterrupt:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        raise


def main():
    parser = argparse.ArgumentParser(description="Sign and verify Ruri Chorus with its pinned Apple Development identity.")
    parser.add_argument("action", choices=["run", "verify", "cleanup-ci"])
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.action == "verify":
        verify(Path(args.arguments[0]), os.environ)
    elif args.action == "cleanup-ci":
        cleanup_ci(os.environ)
    else:
        arguments = args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
        if not arguments:
            raise SigningError("A build command is required.")
        # Normal CI cancellation must still unwind the temporary keychain.
        def cancel(_signal, _frame):
            raise KeyboardInterrupt
        signal.signal(signal.SIGTERM, cancel)
        with signing_environment(os.environ) as environment:
            return run_build(arguments, environment)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (SigningError, OSError) as error:
        sys.exit(f"Signing: {error}")
    except KeyboardInterrupt:
        sys.exit(130)
