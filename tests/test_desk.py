import contextlib
import io
import subprocess
import unittest
from argparse import Namespace
from unittest.mock import patch

from tools import desk


class DeviceSelectionTests(unittest.TestCase):
    def test_unauthorized_device_does_not_trigger_automatic_selection_of_another(self):
        devices = desk.parse_devices(
            "List of devices attached\nBIKE unauthorized usb:1\nPHONE device model:Pixel\n"
        )
        with self.assertRaisesRegex(desk.DeskError, "Plusieurs"):
            desk.select_device(devices)
        with self.assertRaisesRegex(desk.DeskError, "unauthorized"):
            desk.select_device(devices, "BIKE")

    def test_explicit_device_must_be_online(self):
        for state in ("offline", "unauthorized", "recovery"):
            with self.subTest(state=state), self.assertRaises(desk.DeskError):
                desk.select_device({"BIKE": state}, "BIKE")
        self.assertEqual(desk.select_device({"BIKE": "device"}, "BIKE"), "BIKE")

    def test_adb_daemon_messages_are_not_devices(self):
        output = "* daemon started successfully\nList of devices attached\n\n"
        self.assertEqual(desk.parse_devices(output), {})
        with self.assertRaisesRegex(desk.DeskError, "Aucun appareil"):
            desk.select_device({})

    def test_package_filter_does_not_accept_a_fork_as_official_app(self):
        with patch.object(desk, "adb_shell", return_value="package:com.limelight.unofficial"):
            self.assertFalse(desk.installed("BIKE", "com.limelight"))

    def test_package_manager_error_is_not_reported_as_missing_app(self):
        with patch.object(desk, "adb_shell", return_value="Error: device disconnected"):
            with self.assertRaises(desk.DeskError):
                desk.installed("BIKE", "com.limelight")


class LaunchTests(unittest.TestCase):
    def test_bike_dry_run_never_contacts_device(self):
        with patch.object(desk, "run") as runner, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(desk.main([
                "launch-bike", "moonlight", "--serial", "BIKE", "--dry-run"
            ]), 0)
        runner.assert_not_called()

    def test_activity_manager_error_with_success_exit_code_is_reported(self):
        args = Namespace(app="moonlight", serial="BIKE", dry_run=False)
        with patch.object(desk, "run", side_effect=[
            "List of devices attached\nBIKE device", "package:com.limelight",
            "Error: Activity not started, unable to resolve Intent",
        ]):
            with self.assertRaisesRegex(desk.DeskError, "Activity not started"):
                desk.launch_bike(args)

    def test_host_does_not_partially_launch_when_voice_app_missing(self):
        args = Namespace(voice_app="VoiceInk", dry_run=False)
        with patch.object(desk.platform, "system", return_value="Darwin"), \
             patch.object(desk, "app_path", side_effect=["/Applications/Sunshine.app", None]), \
             patch.object(desk, "run") as runner:
            with self.assertRaises(desk.DeskError):
                desk.launch_host(args)
        runner.assert_not_called()

    def test_timeout_is_actionable_error(self):
        with patch.object(desk.subprocess, "run", side_effect=subprocess.TimeoutExpired("adb", 10)):
            with self.assertRaises(desk.DeskError):
                desk.run(["adb", "devices"])


if __name__ == "__main__":
    unittest.main()
