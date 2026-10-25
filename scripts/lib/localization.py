"""Source-literal and relocated-bundle checks for the localization entry point."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import sys
sys.dont_write_bytecode = True
from .swift_strings import Scanner
from .localization_catalog import shipping_languages

HAN = re.compile(r'[\u3400-\u9fff]')
FULL_WIDTH = re.compile(r'[：，。、；！？（）“”]')
UI_ARGUMENT = re.compile(r'(?:Text|Button|Label|Section|Toggle|Picker|TextField|SecureField|ProgressView|ContentUnavailableView|LabeledContent|CommandMenu|navigationTitle|navigationSubtitle|help|accessibilityLabel|alert|confirmationDialog)\(\s*$')
BRANDS = {'Ruri', 'Minecraft', 'Java', 'Microsoft', 'Modrinth', 'CurseForge', 'Fabric', 'Legacy Fabric', 'Quilt', 'Forge', 'NeoForge', 'LiteLoader', 'OptiFine', 'JVM', 'Metaspace', 'PNG', 'UUID', 'API Key', 'Beta', 'Alpha'}


def candidates(root):
    for path in sorted((root / 'Sources').rglob('*.swift')):
        # Message accessors generated for extension modules hold catalog text too.
        if 'RuriLocalization' in path.parts or path.parent.name == 'Generated' and path.parent.parent.name == 'Localization':
            continue
        source = path.read_text()
        scanner = Scanner(source)

        def walk(start=0, end=None):
            for node in scanner.nodes(start, end):
                yield node
                for kind, a, b in node['parts']:
                    if kind == 'expr':
                        yield from walk(a, b)

        for node in walk():
            content = ''.join(source[a:b] for kind, a, b in node['parts'] if kind == 'text')
            prefix = source[max(0, node['start'] - 150):node['start']]
            human = bool(HAN.search(content) or FULL_WIDTH.search(content)) or bool(re.search('[A-Za-z]{3}', content) and ' ' in content)
            human |= bool(UI_ARGUMENT.search(prefix) and re.search('[A-Za-z]', content) and content not in BRANDS)
            if human:
                yield {'file': str(path.relative_to(root)), 'literal': source[node['start']:node['end']],
                       'line': source[:node['start']].count('\n') + 1}
        for start, end in localized_concatenations(source):
            yield {'file': str(path.relative_to(root)), 'literal': source[start:end].strip(),
                   'line': source[:start].count('\n') + 1}


def localized_concatenations(source):
    """Find direct + operands without mistaking comments, strings or += for code."""
    scanner = Scanner(source)
    token = re.compile(r'[A-Za-z_$][A-Za-z0-9_$]*|\+=|\+\+|\S')
    identifiers = re.compile(r'[A-Za-z_$][A-Za-z0-9_$]*')
    found = set()

    def scan(start, end):
        tokens = []
        index = start
        while index < end:
            comment = scanner.comment(index)
            if comment is not None:
                index = comment
                continue
            if scanner.start(index):
                node = scanner.string(index)
                tokens.append(('literal', index, node['end']))
                for kind, a, b in node['parts']:
                    if kind == 'expr':
                        scan(a, b)
                index = node['end']
                continue
            match = token.match(source, index)
            if match:
                tokens.append((match[0], index, match.end()))
                index = match.end()
            else:
                index += 1
        for i, (value, position, _) in enumerate(tokens):
            if value != 'localized' or i < 2 or tokens[i - 1][0] != '.':
                continue
            right = i + 1 < len(tokens) and tokens[i + 1][0] == '+'
            left = i - 2
            while left >= 0:
                value = tokens[left][0]
                if value in {')', ']'}:
                    close, opening, depth = value, '(' if value == ')' else '[', 1
                    left -= 1
                    while left >= 0 and depth:
                        if tokens[left][0] == close: depth += 1
                        if tokens[left][0] == opening: depth -= 1
                        left -= 1
                elif identifiers.fullmatch(value):
                    left -= 1
                    if left >= 0 and tokens[left][0] == '.':
                        left -= 1
                    else:
                        break
                else:
                    break
            if right or (left >= 0 and tokens[left][0] == '+'):
                line_start = source.rfind('\n', 0, position) + 1
                line_end = source.find('\n', position)
                found.add((line_start, len(source) if line_end < 0 else line_end))
    scan(0, len(source))
    return sorted(found)


def check_source_literals(root):
    path = Path(__file__).with_name('localization-exceptions.json')
    exceptions = json.loads(path.read_text())
    allowed = {(entry['file'], entry['literal']) for entry in exceptions if entry.get('reason', '').strip()}
    unresolved = [entry for entry in candidates(root) if (entry['file'], entry['literal']) not in allowed]
    if unresolved:
        raise ValueError('User-facing literals need resources or a reviewed syntax/data exception:\n' + '\n'.join(
            f"{entry['file']}:{entry['line']}: {entry['literal'][:100]}" for entry in unresolved))


def check_bundle(app, cli=None):
    with tempfile.TemporaryDirectory(prefix='ruri-localization-') as directory:
        root = Path(directory)
        moved = root / 'Ruri.app'
        shutil.copytree(app, moved)
        binaries = [moved / 'Contents/MacOS/Ruri', moved / 'Contents/Helpers/ruri-monitor', moved / 'Contents/Helpers/ruri-cli']
        if cli:
            standalone = root / 'bin'
            standalone.mkdir()
            shutil.copy2(cli, standalone / 'ruri-cli')
            for bundle in (moved / 'Contents/Resources').glob('*.bundle'):
                shutil.copytree(bundle, standalone / bundle.name)
            binaries.append(standalone / 'ruri-cli')
        environment = dict(os.environ, RURI_DATA_DIR=str(root / 'untouched-data'), RURI_LANGUAGE='unsupported-language')
        for binary in binaries:
            result = subprocess.run([str(binary), '--localization-check'], env=environment,
                                    check=True, capture_output=True, text=True, timeout=30)
            report = json.loads(result.stdout)
            if not Path(report['bundle']).resolve().is_relative_to(root.resolve()):
                raise RuntimeError(f'{binary.name} used resources outside the relocated package')
            if not report['message'] or 'zh-hans' not in [name.lower() for name in report['languages']]:
                raise RuntimeError(f'{binary.name} did not read the base localization')
            print(f'{binary.name}: relocated localization resources verified')
        if (root / 'untouched-data').exists():
            raise RuntimeError('Resource check unexpectedly initialized launcher data')
        # A missing installed bundle must fail the check, not use the build tree.
        shutil.rmtree(moved / 'Contents/Resources/Ruri_RuriLocalization.bundle')
        for binary in binaries[:3]:
            result = subprocess.run([str(binary), '--localization-check'], env=environment,
                                    capture_output=True, text=True, timeout=30)
            if result.returncode != 2:
                raise RuntimeError(f'{binary.name} failed to detect its missing resource bundle')
