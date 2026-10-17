"""Open only the configured Bike; keep connection credentials out of errors."""
import ipaddress
import os
import re
import secrets
import subprocess
from pathlib import Path

if __package__:
    from .desk import DeskError, parse_devices, run, select_device
else:
    from desk import DeskError, parse_devices, run, select_device

LOCAL = Path(__file__).resolve().parents[1] / '.local'
TLS_SERVICE = '_adb-tls-connect._tcp'


def connection_token():
    LOCAL.mkdir(parents=True, exist_ok=True)
    path = LOCAL / 'connection-token'
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        pass
    else:
        with os.fdopen(fd, 'w') as stream:
            stream.write(secrets.token_urlsafe(32))
    path.chmod(0o600)
    token = path.read_text().strip()
    if not re.fullmatch(r'[A-Za-z0-9_-]{30,100}', token):
        raise DeskError('Le jeton local de connexion est invalide. Réinstaller Peloton Desk.')
    return token


def resolve_bike(serial):
    devices = parse_devices(run(['adb', 'devices', '-l']))
    if devices.get(serial) == 'device':
        return serial
    if devices.get(serial) == 'unauthorized':
        raise DeskError('Acceptez la connexion de ce Mac sur le Bike.')
    match = re.fullmatch(r'adb-([A-Za-z0-9]+)-.+\._adb-tls-connect\._tcp\.?', serial)
    if not match:
        raise DeskError('Bike non connecté. Allumez-le et vérifiez sa connexion ADB.')
    hardware = match.group(1)
    prefix = f'adb-{hardware}-'
    online = [name for name, state in devices.items()
              if name.startswith(prefix) and TLS_SERVICE in name and state == 'device']
    if len(online) > 1:
        raise DeskError('Plusieurs connexions du Bike détectées. Reconnectez uniquement le Bike configuré.')
    candidate = online[0] if online else None
    if candidate is None:
        services = []
        for line in run(['adb', 'mdns', 'services']).splitlines():
            fields = line.split()
            if len(fields) != 3 or fields[1] != TLS_SERVICE or not fields[0].startswith(prefix):
                continue
            address = fields[2]
            try:
                host, port = address.rsplit(':', 1)
                ipaddress.ip_address(host.strip('[]'))
                if not 1 <= int(port) <= 65535: continue
            except ValueError:
                continue
            services.append((fields[0], address))
        if len(services) != 1:
            raise DeskError('Bike introuvable. Allumez-le, connectez-le au même Wi-Fi et activez Wireless debugging.')
        name, address = services[0]
        run(['adb', 'connect', address])
        devices = parse_devices(run(['adb', 'devices', '-l']))
        candidate = next((item for item in (name + '.' + TLS_SERVICE, name + '.' + TLS_SERVICE + '.', address)
                          if devices.get(item) == 'device'), None)
        if candidate is None:
            raise DeskError('Le Bike répond mais refuse la connexion. Vérifiez l’appairage Wireless debugging.')
    # A changed discovery name/address is accepted only for the saved hardware.
    if run(['adb', '-s', candidate, 'shell', 'getprop', 'ro.serialno']).strip() != hardware:
        raise DeskError('L’appareil découvert ne correspond pas au Bike configuré.')
    return select_device(devices, candidate)


def open_desktop(serial, auto_connect=True):
    serial = resolve_bike(serial)
    run(['adb', '-s', serial, 'reverse', 'tcp:8765', 'tcp:8765'])
    token = connection_token()
    command = ['adb', '-s', serial, 'shell', 'am', 'start', '-n',
               'local.pelotondesk/.MainActivity', '--es', 'token', token,
               '--ez', 'desktop', 'true' if auto_connect else 'false']
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        raise DeskError('Le Bike n’a pas répondu à l’ouverture de Peloton Desk.') from None
    if result.returncode or re.search(r'Error:|Exception|Permission Denial', result.stdout + result.stderr):
        raise DeskError('Peloton Desk n’a pas pu s’ouvrir. Vérifiez que l’app est installée sur le Bike.')
    return serial
