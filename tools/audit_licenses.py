"""Check package licenses against the reviewed inventory; run with .venv/bin/python.

This checks metadata and version drift. Vendored code, native libraries and model
weights also need the manual review recorded in THIRD_PARTY.md.
"""
import argparse
from importlib import metadata
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INVENTORY = ROOT / 'docs/license-inventory.json'
ALLOWED = {'MIT', 'MPL-2.0', 'Apache-2.0', 'Apache-2.0 AND MIT',
           'BSD-3-Clause', 'PSF-2.0', 'MIT-CMU'}


def collect():
    components = []
    lock = json.loads((ROOT / 'package-lock.json').read_text())
    for name, package in lock['packages'].items():
        if name:
            components.append({'ecosystem': 'npm', 'name': name.removeprefix('node_modules/'),
                               'version': package['version'], 'license': package.get('license'),
                               'scope': 'build' if package.get('dev') else 'runtime'})
    for package in metadata.distributions():
        license_id = package.metadata.get('License-Expression') or package.metadata.get('License')
        if license_id == 'Apache 2.0': license_id = 'Apache-2.0'
        components.append({'ecosystem': 'python', 'name': package.metadata['Name'].lower(),
                           'version': package.version, 'license': license_id, 'scope': 'runtime'})
    pins = json.loads((ROOT / 'macos/parakeet/Package.resolved').read_text())['pins']
    for pin in pins:
        # This exact source revision was manually reviewed, including vendored code.
        reviewed = (pin['identity'] == 'fluidaudio' and
                    pin['state']['revision'] == '503b4bd1bbf7220882de39fe8ae6716aae4132da')
        components.append({'ecosystem': 'swift', 'name': pin['identity'],
                           'version': pin['state']['version'], 'revision': pin['state']['revision'],
                           'license': 'Apache-2.0' if reviewed else None, 'scope': 'runtime'})
    return sorted(components, key=lambda c: (c['ecosystem'], c['name']))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true', help='Save the reviewed package inventory')
    args = parser.parse_args()
    components = collect()
    unknown = [c for c in components if c['license'] not in ALLOWED]
    if unknown:
        for component in unknown:
            print('REVIEW', component['ecosystem'], component['name'], component['version'], component['license'])
        return 1
    if args.write:
        INVENTORY.write_text(json.dumps({'reviewed_on': '2026-10-17',
            'manual_review': '../THIRD_PARTY.md', 'components': components}, indent=2) + '\n')
    elif not INVENTORY.exists() or json.loads(INVENTORY.read_text())['components'] != components:
        print('REVIEW: package versions/licenses changed; update the audit before accepting a new inventory.')
        return 1
    counts = {kind: sum(c['ecosystem'] == kind for c in components) for kind in ('npm', 'python', 'swift')}
    print('License metadata matches reviewed inventory:', json.dumps(counts))
    print('MPL-2.0 present (noVNC). See THIRD_PARTY.md for source, attribution and model obligations.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
