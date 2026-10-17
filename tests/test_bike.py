import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import bike

SERIAL = 'adb-BIKE123-old._adb-tls-connect._tcp'
TOKEN = 'test-connection-token-that-must-stay-private'


class BikeShortcutTests(unittest.TestCase):
    def test_shortcut_targets_configured_bike_and_requests_desktop(self):
        with patch.object(bike, 'run', side_effect=[f'{SERIAL} device\nPHONE device', '']) as runner, \
             patch.object(bike, 'connection_token', return_value=TOKEN), \
             patch.object(bike.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'Starting', '')) as launch:
            self.assertEqual(bike.open_desktop(SERIAL), SERIAL)
        self.assertEqual(runner.call_args_list[-1].args[0], ['adb', '-s', SERIAL, 'reverse', 'tcp:8765', 'tcp:8765'])
        command = launch.call_args.args[0]
        self.assertEqual(command[:3], ['adb', '-s', SERIAL])
        self.assertEqual(command[-3:], ['--ez', 'desktop', 'true'])

    def test_timeout_does_not_expose_connection_token(self):
        with patch.object(bike, 'resolve_bike', return_value=SERIAL), patch.object(bike, 'run'), \
             patch.object(bike, 'connection_token', return_value=TOKEN), \
             patch.object(bike.subprocess, 'run', side_effect=subprocess.TimeoutExpired(['adb', TOKEN], 30)):
            with self.assertRaises(bike.DeskError) as caught:
                bike.open_desktop(SERIAL)
        self.assertNotIn(TOKEN, str(caught.exception))
        self.assertTrue(caught.exception.__suppress_context__)

    def test_android_error_with_zero_exit_is_not_reported_as_success(self):
        with patch.object(bike, 'resolve_bike', return_value=SERIAL), patch.object(bike, 'run'), \
             patch.object(bike, 'connection_token', return_value=TOKEN), \
             patch.object(bike.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'Error: Activity does not exist', '')):
            with self.assertRaises(bike.DeskError):
                bike.open_desktop(SERIAL)

    def test_reconnect_uses_tls_discovery_and_checks_hardware_identity(self):
        discovered = 'adb-BIKE123-new'
        address = '192.0.2.20:40000'
        answers = ['', f'{discovered}\t_adb-tls-connect._tcp\t{address}\n', 'connected', f'{address} device\n', 'BIKE123']
        with patch.object(bike, 'run', side_effect=answers) as runner:
            self.assertEqual(bike.resolve_bike(SERIAL), address)
        self.assertEqual(runner.call_args_list[2].args[0], ['adb', 'connect', address])
        self.assertEqual(runner.call_args_list[-1].args[0], ['adb', '-s', address, 'shell', 'getprop', 'ro.serialno'])

    def test_wrong_hardware_at_discovered_address_is_refused(self):
        online = 'adb-BIKE123-new._adb-tls-connect._tcp'
        with patch.object(bike, 'run', side_effect=[f'{online} device', 'OTHERBIKE']):
            with self.assertRaisesRegex(bike.DeskError, 'ne correspond pas'):
                bike.resolve_bike(SERIAL)

    def test_offline_bike_does_not_connect_to_other_devices_or_legacy_adb(self):
        with patch.object(bike, 'run', side_effect=['PHONE device',
                'adb-PHONE-x\t_adb-tls-connect._tcp\t192.0.2.10:40000\n'
                'adb-BIKE123\t_adb._tcp\t192.0.2.20:5555']) as runner:
            with self.assertRaisesRegex(bike.DeskError, 'introuvable'):
                bike.resolve_bike(SERIAL)
        self.assertFalse(any('connect' in call.args[0] for call in runner.call_args_list))

    def test_token_is_private_and_reused_across_launches(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(bike, 'LOCAL', Path(directory)):
            first = bike.connection_token()
            self.assertEqual(first, bike.connection_token())
            self.assertEqual((Path(directory) / 'connection-token').stat().st_mode & 0o777, 0o600)


if __name__ == '__main__':
    unittest.main()
