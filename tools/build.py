#!/usr/bin/env python3
"""Build the Android APK and native Mac launcher with the installed SDKs."""
import argparse
import os
import plistlib
import shutil
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / '.local'


def run(*args):
    subprocess.run([str(a) for a in args], cwd=ROOT, check=True)


def android():
    sdk = Path(os.environ.get('ANDROID_SDK_ROOT', LOCAL / 'android-sdk'))
    tools = sdk / 'build-tools/35.0.1'
    jar = sdk / 'platforms/android-35/android.jar'
    if not jar.exists() or not tools.exists():
        raise SystemExit('Android SDK missing. Install platforms;android-35 and build-tools;35.0.1 after accepting the SDK license.')
    out = LOCAL / 'build/android'
    classes, dex = out / 'classes', out / 'dex'
    for path in (classes, dex):
        if path.exists(): shutil.rmtree(path)
        path.mkdir(parents=True)
    run('javac', '--release', '8', '-classpath', jar, '-d', classes, *sorted((ROOT / 'android/src').rglob('*.java')))
    run(tools / 'd8', '--lib', jar, '--min-api', '26', '--output', dex, *sorted(classes.rglob('*.class')))
    run(tools / 'aapt2', 'compile', '--dir', ROOT / 'android/res', '-o', out / 'resources.zip')
    run(tools / 'aapt2', 'link', '-I', jar, '--manifest', ROOT / 'android/AndroidManifest.xml',
        '--debug-mode', '--version-code', '1', '--version-name', '0.1.0', '-o', out / 'unsigned.apk', out / 'resources.zip')
    with zipfile.ZipFile(out / 'unsigned.apk', 'a', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in dex.glob('*.dex'): archive.write(path, path.name)
    key = LOCAL / 'debug.keystore'
    if not key.exists():
        run('keytool', '-genkeypair', '-keystore', key, '-storepass', 'android', '-keypass', 'android',
            '-alias', 'androiddebugkey', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000', '-dname', 'CN=Peloton Desk Development')
        key.chmod(0o600)
    apk = LOCAL / 'build/peloton-desk.apk'
    run(tools / 'zipalign', '-f', '4', out / 'unsigned.apk', apk)
    run(tools / 'apksigner', 'sign', '--ks', key, '--ks-key-alias', 'androiddebugkey',
        '--ks-pass', 'pass:android', '--key-pass', 'pass:android', apk)
    run(tools / 'apksigner', 'verify', apk)
    print(apk)


def mac():
    app = LOCAL / 'Peloton Desk Mac.app'
    contents = app / 'Contents'
    binary = contents / 'MacOS/PelotonDesk'
    binary.parent.mkdir(parents=True, exist_ok=True)
    info = {'CFBundleIdentifier': 'local.pelotondesk.mac', 'CFBundleName': 'Peloton Desk Mac',
            'CFBundleExecutable': 'PelotonDesk', 'CFBundlePackageType': 'APPL',
            'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '1', 'LSUIElement': True,
            'LSMinimumSystemVersion': '14.0', 'PDProjectRoot': str(ROOT),
            'NSMicrophoneUsageDescription': 'Transcrire localement votre voix quand vous activez la dictée sur le Bike.'}
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    run('swiftc', '-swift-version', '5', '-O', '-framework', 'AppKit', '-framework', 'AVFoundation',
        '-framework', 'ApplicationServices', ROOT / 'macos/Companion.swift', '-o', binary)
    run('codesign', '--force', '--sign', '-', app)
    print(app)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('target', choices=('android', 'mac'))
    args = parser.parse_args()
    (android if args.target == 'android' else mac)()
