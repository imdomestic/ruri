"""Read String Catalogs and validate the formats used by typed messages."""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import sys
sys.dont_write_bytecode = True

BASE_LANGUAGE = 'zh-Hans'
CLI_LANGUAGES = ['en', BASE_LANGUAGE]
CLI_TABLES = {'CLIInterface', 'CLIExperience', 'CLISetup', 'Progress'}
SHIP_THRESHOLD = 0.95
REQUIRED_COMPLETE = {'en'}
# Integer cardinal categories from CLDR 48, common/supplemental/plurals.xml:
# https://github.com/unicode-org/cldr/blob/release-48/common/supplemental/plurals.xml
# Foundation also requires an `other` fallback, even for languages whose
# integer values never select it (ru, uk and pl).
INTEGER_PLURALS = {
    'en': {'one', 'other'}, 'de': {'one', 'other'},
    'fr': {'one', 'many', 'other'}, 'es': {'one', 'many', 'other'},
    'it': {'one', 'many', 'other'}, 'pt-BR': {'one', 'many', 'other'},
    'ja': {'other'}, 'ko': {'other'}, 'zh-Hans': {'other'}, 'zh-Hant': {'other'},
    'ru': {'one', 'few', 'many'}, 'uk': {'one', 'few', 'many'}, 'pl': {'one', 'few', 'many'},
}
FORMAT = re.compile(r'%(?:(\d+)\$)?(lld|@|g|f|d|%)')
SUBSTITUTION = re.compile(r'%(?:(\d+)\$)?#@([A-Za-z][A-Za-z0-9_]*)@')
PLURAL_CATEGORIES = {'zero', 'one', 'two', 'few', 'many', 'other'}
SWIFT_KEYWORDS = set('associatedtype borrowing class consuming deinit enum extension fileprivate func import init inout internal let nonisolated open operator precedencegroup private protocol public rethrows some static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw switch where while as Any false is nil self Self super throws true try _ actor any async await distributed dynamic final get indirect infix isolated lazy left macro mutating none nonmutating optional override package postfix prefix required right set unowned weak willSet didSet convenience'.split())


def read_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f'{path}: duplicate JSON key: {key}')
            result[key] = value
        return result
    return json.loads(path.read_text(), object_pairs_hook=unique)


def catalog_text(value):
    # Match Xcode's stable, sorted String Catalog representation.
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True, separators=(',', ' : ')) + '\n'


def signature(value):
    result = {}
    position = 0
    cursor = 0
    for match in FORMAT.finditer(value):
        if '%' in value[cursor:match.start()]:
            raise ValueError('Unsupported format token in ' + value)
        cursor = match.end()
        index, kind = match.groups()
        if kind == '%':
            continue
        position += 1
        index = int(index) if index else position
        if index < 1:
            raise ValueError('Argument positions start at 1: ' + value)
        resolved = 'integer' if kind in ('lld', 'd') else 'text' if kind == '@' else 'decimal'
        if index in result and result[index] != resolved:
            raise ValueError('Inconsistent argument in ' + value)
        result[index] = resolved
    if '%' in value[cursor:]:
        raise ValueError('Unescaped percent in ' + value)
    return result


def unit_value(node):
    unit = node.get('stringUnit', {})
    value = unit.get('value')
    if not isinstance(value, str) or unit.get('state') not in {'translated', 'needs_review', 'new'}:
        raise ValueError('Missing string value or invalid translation state')
    return value


def plural_variants(node):
    if set(node.get('variations', {})) != {'plural'}:
        raise ValueError('Only plural variations are supported')
    variants = node['variations']['plural']
    if not isinstance(variants, dict) or 'other' not in variants or not set(variants) <= PLURAL_CATEGORIES:
        raise ValueError('Invalid plural categories; other is required')
    return {category: unit_value(variant) for category, variant in variants.items()}


def localization_value(node):
    """Return the fallback format, signature and the plural argument positions."""
    if not isinstance(node, dict):
        raise ValueError('Localization must be an object')
    if 'variations' in node:
        if 'stringUnit' in node or 'substitutions' in node:
            raise ValueError('A plural cannot also contain a stringUnit or substitutions')
        variants = plural_variants(node)
        value = variants['other']
        expected = signature(value)
        numeric = [int(m[1]) if m[1] else index + 1 for index, m in enumerate(m for m in FORMAT.finditer(value) if m[2] != '%') if m[2] in {'lld', 'd'}]
        if not numeric:
            raise ValueError('Plural variant must contain its numeric argument')
        argument = numeric[0]
        for text in variants.values():
            if signature(text) != expected or signature(text).get(argument) != 'integer':
                raise ValueError('Plural variant changes parameters or omits its numeric argument')
        return value, expected, {argument}
    value = unit_value(node)
    substitutions = node.get('substitutions', {})
    if not substitutions:
        return value, signature(value), set()
    references = list(SUBSTITUTION.finditer(value))
    if set(m[2] for m in references) != set(substitutions):
        raise ValueError('Unknown or unused plural substitution')
    plural_arguments = set()
    for match in references:
        rule = substitutions[match[2]]
        argument = rule.get('argNum')
        if type(argument) is not int or argument < 1 or rule.get('formatSpecifier') not in {'lld', 'd'}:
            raise ValueError('Invalid plural substitution argument')
        if match[1] and int(match[1]) != argument:
            raise ValueError('Substitution position differs from argNum')
        if argument in plural_arguments:
            raise ValueError('Duplicate plural argument')
        plural_arguments.add(argument)
        for text in plural_variants(rule).values():
            # Substitutions format their own value; other arguments belong to
            # the outer format or to a whole-message plural variation.
            if (signature(text) not in ({1: 'integer'}, {argument: 'integer'})
                    or any(token[1] and int(token[1]) != argument for token in FORMAT.finditer(text) if token[2] != '%')):
                raise ValueError('Plural variant must format its own numeric argument')
    def expand(match):
        rule = substitutions[match[2]]
        text = plural_variants(rule)['other']
        return FORMAT.sub(lambda token: token[0] if token[2] == '%' else f'%{rule["argNum"]}${token[2]}', text)
    value = SUBSTITUTION.sub(expand, value)
    return value, signature(value), plural_arguments


def read_catalogs(root, check_format=False, format_files=False):
    resources = root / 'Sources/RuriLocalization/Resources'
    catalogs = {}
    keys = set()
    # Extension modules keep their own catalogs in Sources/<Module>/Localization/Resources.
    paths = sorted([*resources.glob('*.xcstrings'), *root.glob('Sources/*/Localization/Resources/*.xcstrings')])
    if not paths:
        raise ValueError('No String Catalogs found')
    for path in paths:
        catalog = read_json(path)
        if catalog.get('sourceLanguage') != BASE_LANGUAGE or catalog.get('version') != '1.0':
            raise ValueError(f'{path}: expected zh-Hans String Catalog version 1.0')
        canonical = catalog_text(catalog)
        if format_files:
            path.write_text(canonical)
        elif check_format and path.read_text() != canonical:
            raise ValueError(f'{path}: noncanonical formatting; run scripts/localization.py --format')
        for key, entry in catalog['strings'].items():
            identity = path.stem + ':' + key
            if not re.fullmatch(r'[A-Z][A-Za-z0-9]*\.[a-z][A-Za-z0-9]*', key):
                raise ValueError('Invalid Group.name key: ' + identity)
            group, name = key.split('.')
            if group in SWIFT_KEYWORDS or name in SWIFT_KEYWORDS or name == 'definitions':
                raise ValueError('Reserved Swift identifier: ' + identity)
            if key in keys:
                raise ValueError('Duplicate message key: ' + key)
            keys.add(key)
            if entry.get('extractionState') != 'manual':
                raise ValueError('Messages must use manual extraction: ' + identity)
            localizations = entry.get('localizations', {})
            if BASE_LANGUAGE not in localizations:
                raise ValueError('Unknown key without a source localization: ' + identity)
            try:
                value, expected, plurals = localization_value(localizations[BASE_LANGUAGE])
                if expected and not entry.get('comment', '').strip():
                    raise ValueError('Messages with placeholders need a translator comment')
                if set(expected) != set(range(1, len(expected) + 1)):
                    raise ValueError('Format argument positions must be contiguous')
                for language, localization in localizations.items():
                    if localization_value(localization)[1] != expected:
                        raise ValueError(language + ': translation changes parameters')
            except (ValueError, KeyError, TypeError) as error:
                raise ValueError(f'{identity}: {error}') from error
            catalogs[identity] = {'table': path.stem, 'key': key, 'group': group, 'name': name,
                                  'value': value, 'kinds': [expected[i + 1] for i in range(len(expected))],
                                  'plurals': plurals, 'entry': entry, 'module': path.relative_to(root / 'Sources').parts[0],
                                  'output': resources.parent / 'Generated' if path.parent == resources else path.parent.parent / 'Generated'}
    return catalogs


def plural_rule(specifier, variants):
    return {'NSStringFormatSpecTypeKey': 'NSStringPluralRuleType', 'NSStringFormatValueTypeKey': specifier, **variants}


def compiled_entry(node):
    """Return a .strings value, or a .stringsdict entry for plurals, as xcstringstool writes them."""
    if 'variations' in node:
        variants = plural_variants(node)
        (argument,) = localization_value(node)[2]
        tokens = [m for m in FORMAT.finditer(variants['other']) if m[2] != '%']
        specifier = next(m[2] for position, m in enumerate(tokens, 1) if (int(m[1]) if m[1] else position) == argument)
        key = '%#@value@' if argument == 1 else f'%{argument}$#@value@'
        return {'NSStringLocalizedFormatKey': key, 'value': plural_rule(specifier, variants)}
    entry = {'NSStringLocalizedFormatKey': unit_value(node)}
    for name, rule in node.get('substitutions', {}).items():
        entry[name] = plural_rule(rule['formatSpecifier'], plural_variants(rule))
    return entry if len(entry) > 1 else entry['NSStringLocalizedFormatKey']


def compile_catalogs(root, bundle):
    """Replace the String Catalogs SwiftPM copies into a bundle without Xcode with compiled tables."""
    tables = {}
    for item in read_catalogs(root).values():
        # SwiftPM names each module's resource bundle Ruri_<Module>.bundle.
        if bundle.name != 'Ruri_' + item['module'] + '.bundle':
            continue
        for language, node in item['entry']['localizations'].items():
            entry = compiled_entry(node)
            kind = 'stringsdict' if isinstance(entry, dict) else 'strings'
            tables.setdefault((language, item['table'], kind), {})[item['key']] = entry
    if not tables:
        raise ValueError('No String Catalogs for bundle: ' + str(bundle))
    for (language, table, kind), entries in tables.items():
        path = bundle / f'{language}.lproj/{table}.{kind}'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(plistlib.dumps(entries))
    for catalog in bundle.glob('*.xcstrings'):
        catalog.unlink()


def source_hash(item):
    def semantic(node):
        if isinstance(node, dict):
            return {key: semantic(value) for key, value in node.items() if key != 'state'}
        return node
    source = semantic(item['entry']['localizations'][BASE_LANGUAGE])
    value = json.dumps(source, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    return hashlib.sha256(value.encode()).hexdigest()[:12]


def baseline_path(root):
    return root / 'scripts/lib/localization-baseline.json'


def read_baseline(root):
    path = baseline_path(root)
    baseline = read_json(path) if path.exists() else {}
    if not isinstance(baseline, dict) or any(
        not isinstance(items, dict) or any(not isinstance(value, str) or not re.fullmatch(r'[0-9a-f]{12}', value) for value in items.values())
        for items in baseline.values()
    ):
        raise ValueError('Invalid translation baseline')
    return baseline


def coverage(catalogs, baseline):
    languages = {BASE_LANGUAGE, 'en'} | set(baseline)
    for item in catalogs.values():
        languages.update(item['entry']['localizations'])
    result = {}
    for language in sorted(languages):
        missing, stale, valid = [], [], []
        for identity, item in catalogs.items():
            if language not in item['entry']['localizations']:
                missing.append(identity)
            elif language != BASE_LANGUAGE and baseline.get(language, {}).get(identity) != source_hash(item):
                stale.append(identity)
            else:
                valid.append(identity)
        result[language] = {'missing': missing, 'stale': stale, 'valid': valid,
                            'coverage': len(valid) / len(catalogs) if catalogs else 1.0}
    return result


def accept_translations(root, catalogs, language, keys=None, accept_all=False):
    if language not in INTEGER_PLURALS or language == BASE_LANGUAGE:
        raise ValueError('Choose a translation language listed in INTEGER_PLURALS')
    if accept_all:
        selected = [identity for identity, item in catalogs.items() if language in item['entry']['localizations']]
    else:
        aliases = {item['key']: identity for identity, item in catalogs.items()}
        selected = [aliases.get(key, key) for key in keys or []]
        if not selected:
            raise ValueError('--accept requires --keys or --all')
    for identity in selected:
        if identity not in catalogs or language not in catalogs[identity]['entry']['localizations']:
            raise ValueError('Cannot accept a missing translation: ' + identity)
    baseline = read_baseline(root)
    accepted = baseline.setdefault(language, {})
    for identity in selected:
        accepted[identity] = source_hash(catalogs[identity])
    baseline_path(root).write_text(json.dumps(baseline, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
    return len(selected)


def validate_policy(root, catalogs):
    path = root / 'scripts/lib/localization-plural-exempt.json'
    exemptions = read_json(path) if path.exists() else []
    allowed = set()
    for entry in exemptions:
        key = entry.get('key')
        if key in allowed or key not in catalogs or not entry.get('reason', '').strip():
            raise ValueError('Invalid or duplicate plural exemption: ' + str(key))
        if 'integer' not in catalogs[key]['kinds'] or catalogs[key]['plurals']:
            raise ValueError('Unnecessary plural exemption: ' + key)
        allowed.add(key)
    for identity, item in catalogs.items():
        if 'integer' in item['kinds'] and not item['plurals'] and identity not in allowed:
            raise ValueError('Integer message needs a plural or a reviewed exemption: ' + identity)
        for language, node in item['entry']['localizations'].items():
            if language not in INTEGER_PLURALS:
                raise ValueError(f'{language}: add its CLDR integer categories to INTEGER_PLURALS first')
            required = INTEGER_PLURALS[language] | {'other'}
            _, _, arguments = localization_value(node)
            if item['plurals'] and required != {'other'} and arguments != item['plurals']:
                raise ValueError(f'{identity} ({language}): translation must pluralize the source count arguments')
            rules = [node] if 'variations' in node else list(node.get('substitutions', {}).values())
            for rule in rules:
                if not required <= set(plural_variants(rule)):
                    raise ValueError(f'{identity} ({language}): missing plural categories {sorted(required - set(plural_variants(rule)))}')
    return coverage(catalogs, read_baseline(root))


def check_completeness(catalogs, status):
    for language in REQUIRED_COMPLETE:
        row = status.get(language)
        if not row or row['missing'] or row['stale']:
            raise ValueError(f'{language}: required localization has missing or stale translations')
    row = status['en']
    incomplete = [key for key in row['missing'] + row['stale'] if catalogs[key]['table'] in CLI_TABLES]
    if incomplete:
        raise ValueError('Missing or stale CLI English translations: ' + ', '.join(incomplete))


def shipping_languages(root, catalogs=None, status=None):
    catalogs = read_catalogs(root) if catalogs is None else catalogs
    status = validate_policy(root, catalogs) if status is None else status
    check_completeness(catalogs, status)
    return sorted(language for language, row in status.items() if language == BASE_LANGUAGE or row['coverage'] >= SHIP_THRESHOLD)
