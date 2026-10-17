#!/usr/bin/env python3
"""Local diagnostics and explicit app launches for a Peloton/Mac workstation."""

import argparse
import json
import platform
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


PACKAGES = {"moonlight": "com.limelight", "metrics": "com.spop.poverlay"}
ACTIVITIES = {"moonlight": ".PcView", "metrics": ".MainActivity"}
TIMEOUT = 10


class DeskError(Exception):
    pass


def run(argv, *, include_stderr=False):
    try:
        result = subprocess.run(
            argv, text=True, capture_output=True, timeout=TIMEOUT, check=False
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise DeskError(f"{argv[0]} : {exc}") from exc
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise DeskError(f"{argv[0]} : {detail or 'échec de la commande'}")
    output = result.stdout
    if include_stderr and result.stderr:
        output += "\n" + result.stderr
    return output.strip()


def app_path(name):
    # App names, not arbitrary commands or paths, are accepted by this helper.
    if not name or name in {".", ".."} or any(c in name for c in "/\\\n\r"):
        raise DeskError("Indiquer un nom d’application, par exemple VoiceInk.")
    bundle = name if name.endswith(".app") else f"{name}.app"
    for directory in (Path("/Applications"), Path.home() / "Applications"):
        candidate = directory / bundle
        if candidate.is_dir():
            return candidate
    return None


def parse_devices(output):
    devices = {}
    for line in output.splitlines():
        fields = line.split()
        if len(fields) < 2 or line.startswith(("List of devices", "*")):
            continue
        devices[fields[0]] = fields[1]
    return devices


def select_device(devices, serial=None):
    if serial is None:
        if not devices:
            raise DeskError("Aucun appareil ADB connecté. Connecter et autoriser le Bike en Wi-Fi ou USB.")
        if len(devices) != 1:
            raise DeskError("Plusieurs appareils ADB : préciser --serial.")
        serial = next(iter(devices))
    state = devices.get(serial)
    if state != "device":
        raise DeskError(f"Appareil {serial} : {state or 'absent'} ; connexion autorisée requise.")
    return serial


def adb_shell(serial, *args):
    return run(["adb", "-s", serial, "shell", *args])


def installed(serial, package):
    output = adb_shell(serial, "pm", "list", "packages", package)
    lines = output.splitlines()
    if any(not line.startswith("package:") for line in lines):
        raise DeskError(f"Réponse inattendue de pm list packages pour {package} : {output}")
    # The Android filter is a substring search; forks must not count as the official app.
    return f"package:{package}" in lines


def doctor(args):
    checks = []

    def record(name, ok, detail):
        checks.append({"name": name, "ok": ok, "detail": detail})

    record("macOS", platform.system() == "Darwin",
           f"{platform.system()} {platform.mac_ver()[0]} · {platform.machine()}")
    for label, name in (("Sunshine", "Sunshine"), ("Dictée", args.voice_app)):
        path = app_path(name)
        record(label, path is not None, str(path) if path else f"{name}.app non trouvé")
    adb = shutil.which("adb")
    record("ADB", adb is not None, adb or "Installer Android Platform Tools")
    if adb:
        try:
            devices = parse_devices(run(["adb", "devices", "-l"]))
            serial = select_device(devices, args.serial)
            model = adb_shell(serial, "getprop", "ro.product.model")
            release = adb_shell(serial, "getprop", "ro.build.version.release")
            sdk = adb_shell(serial, "getprop", "ro.build.version.sdk")
            build = adb_shell(serial, "getprop", "ro.build.display.id")
            record("Bike", True, f"{serial} · {model} · Android {release} · {build}")
            record("Android API", sdk.isdigit() and int(sdk) >= 21,
                   f"API {sdk or 'inconnue'} ; les versions consultées exigent API 21+")
            for label, package in PACKAGES.items():
                present = installed(serial, package)
                record(label, present, f"{package} : {'installé' if present else 'absent'}")
        except DeskError as exc:
            record("Connexion Bike", False, str(exc))
    report = {
        "prerequisites_present": all(check["ok"] for check in checks),
        "checks": checks,
        "manual_checks": [
            "Autorisations macOS de Sunshine et du logiciel de dictée",
            "Appairage Moonlight et qualité du bureau transmis",
            "Toucher un champ puis dicter sans déplacer le focus",
            "Valeurs réelles et chronomètre Grupetto au-dessus de Moonlight",
        ],
    }
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        for check in checks:
            print(f"{'OK' if check['ok'] else 'À FAIRE'}  {check['name']} — {check['detail']}")
        print("Prévol uniquement : tactile, dictée et métriques restent à tester sur le Bike.")
    return 0 if report["prerequisites_present"] else 1


def host_commands(voice_app, dry_run=False):
    commands = []
    for name in dict.fromkeys(("Sunshine", voice_app)):
        path = app_path(name)
        if path is None and not dry_run:
            raise DeskError(f"{name}.app absent de /Applications ou ~/Applications.")
        commands.append(["open", "-g", "-a", str(path) if path else name])
    return commands


def launch_host(args):
    if platform.system() != "Darwin":
        raise DeskError("launch-host nécessite macOS.")
    # Resolve every app first, so a missing app does not cause a partial launch.
    commands = host_commands(args.voice_app, args.dry_run)
    for command in commands:
        print(shlex.join(command))
        if not args.dry_run:
            run(command)
    if not args.dry_run:
        print("Ouverture demandée en arrière-plan. Aucun enregistrement vocal déclenché.")
    return 0


def launch_bike(args):
    package = PACKAGES[args.app]
    # This Bike's firmware rejects package-scoped launcher intents; explicit activities work.
    command = ["adb", "-s", args.serial, "shell", "am", "start", "-W",
               "-n", f"{package}/{ACTIVITIES[args.app]}"]
    if args.dry_run:
        print(shlex.join(command))
        return 0
    serial = select_device(parse_devices(run(["adb", "devices", "-l"])), args.serial)
    if not installed(serial, package):
        raise DeskError(f"{package} absent. Installer l’application avec OpenPelo.")
    output = run(command, include_stderr=True)
    # Android's Activity Manager can print a failure while returning exit code 0.
    if re.search(r"Error(?:\s+type\s+\d+|:)|Exception|Status:\s*timeout", output):
        raise DeskError(output)
    print(output)
    print("Application ouverte ; l’appairage ou l’activation de l’overlay peut rester nécessaire.")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    check = subparsers.add_parser("doctor", help="Vérifier les prérequis sans modifier les réglages")
    check.add_argument("--serial")
    check.add_argument("--voice-app", default="VoiceInk")
    check.add_argument("--json", action="store_true")
    check.set_defaults(handler=doctor)
    host = subparsers.add_parser("launch-host", help="Ouvrir Sunshine et la dictée en arrière-plan")
    host.add_argument("--voice-app", default="VoiceInk")
    host.add_argument("--dry-run", action="store_true")
    host.set_defaults(handler=launch_host)
    bike = subparsers.add_parser("launch-bike", help="Ouvrir une application déjà installée sur le Bike")
    bike.add_argument("app", choices=PACKAGES)
    bike.add_argument("--serial", required=True)
    bike.add_argument("--dry-run", action="store_true")
    bike.set_defaults(handler=launch_bike)
    args = parser.parse_args(argv)
    try:
        return args.handler(args)
    except DeskError as exc:
        print(f"Erreur : {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
