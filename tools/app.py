#!/usr/bin/env python3
"""Install and diagnose the unified Peloton Desk app."""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from desk import DeskError, run, installed, parse_devices, select_device
from bike import open_desktop

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / '.local'
PACKAGE = 'local.pelotondesk'


def install(args):
    apk, bundle = LOCAL / 'build/peloton-desk.apk', LOCAL / 'Peloton Desk Mac.app'
    if not apk.is_file() or not (bundle / 'Contents/MacOS/PelotonDesk').is_file():
        raise DeskError('Compiler d’abord les applications avec make app-build.')
    serial = select_device(parse_devices(run(['adb', 'devices', '-l'])), args.serial)
    subprocess.run(['adb', '-s', serial, 'install', '-r', str(apk)], check=True, timeout=120)
    if not installed(serial, PACKAGE):
        raise DeskError('Le paquet Android n’est pas détecté après installation.')
    destination = Path('/Applications/Peloton Desk Mac.app')
    if destination.exists():
        import plistlib
        info = plistlib.loads((destination / 'Contents/Info.plist').read_bytes())
        if info.get('CFBundleIdentifier') != 'local.pelotondesk.mac':
            raise DeskError('Une autre application porte déjà ce nom dans /Applications.')
    subprocess.run(['ditto', str(bundle), str(destination)], check=True, timeout=30)
    config = LOCAL / 'connection.json'
    config.write_text(json.dumps({'serial': serial}) + '\n')
    config.chmod(0o600)
    print('Peloton Desk installé sur le Bike et dans /Applications/Peloton Desk Mac.app.')


def doctor(args):
    checks = [
        ('Interface compilée', (LOCAL / 'web/app.js').is_file()),
        ('APK compilé', (LOCAL / 'build/peloton-desk.apk').is_file()),
        ('Compagnon Mac compilé', (LOCAL / 'Peloton Desk Mac.app/Contents/MacOS/PelotonDesk').is_file()),
        ('Whisper local', shutil.which('whisper-cli') is not None),
        ('Modèle multilingue', (LOCAL / 'models/ggml-base.bin').is_file()),
    ]
    try:
        serial = select_device(parse_devices(run(['adb', 'devices', '-l'])), args.serial)
        checks.append(('Peloton Desk installé sur le Bike', installed(serial, PACKAGE)))
    except DeskError as exc:
        checks.append((str(exc), False))
    for name, ok in checks: print(('OK  ' if ok else 'À FAIRE  ') + name)
    print('À valider sur le matériel : partage d’écran, tactile, capteurs réels, micro et insertion.')
    return 0 if all(ok for _, ok in checks) else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    command = sub.add_parser('install'); command.add_argument('--serial', required=True)
    command = sub.add_parser('doctor'); command.add_argument('--serial')
    command = sub.add_parser('open'); command.add_argument('--serial', required=True)
    args = parser.parse_args()
    try:
        if args.action == 'install': install(args); return 0
        if args.action == 'open':
            open_desktop(args.serial)
            print('Bureau ouvert sur le Bike.')
            return 0
        return doctor(args)
    except (DeskError, OSError, ValueError, subprocess.SubprocessError) as exc:
        print('Erreur : ' + str(exc), file=sys.stderr); return 2


if __name__ == '__main__': sys.exit(main())
