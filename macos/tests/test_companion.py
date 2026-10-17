import asyncio
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch

from aiohttp import CookieJar, WSServerHandshakeError
from aiohttp.test_utils import TestClient, TestServer, unused_port
from macos.companion import create_app, TOKEN, VOICE, CLIENTS


class GatewayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        port = unused_port()
        self.origin = f'http://127.0.0.1:{port}'
        self.app = create_app('test-token-long-enough-for-this-fixture', self.origin)
        self.client = TestClient(TestServer(self.app, port=port), cookie_jar=CookieJar(unsafe=True))
        await self.client.start_server()

    async def asyncTearDown(self):
        await self.client.close()

    async def authenticate(self):
        response = await self.client.post('/api/auth', json={'token': self.app[TOKEN]}, headers={'Origin': self.origin})
        self.assertEqual(response.status, 200)

    async def test_protected_endpoints_reject_missing_session(self):
        response = await self.client.get('/api/status')
        self.assertEqual(response.status, 401)
        with self.assertRaises(WSServerHandshakeError) as caught:
            await self.client.ws_connect('/vnc', headers={'Origin': self.origin})
        self.assertEqual(caught.exception.status, 401)

    async def test_other_websites_cannot_start_audio_or_establish_session(self):
        await self.authenticate()
        for route, body in [('/api/auth', {'token': self.app[TOKEN]}), ('/api/voice/start', {})]:
            response = await self.client.post(route, json=body, headers={'Origin': 'https://other.example'})
            self.assertEqual(response.status, 403)
        self.assertIsNone(self.app[VOICE].process)

    async def test_rebinding_host_is_rejected(self):
        response = await self.client.get('/', headers={'Host': 'other.example'})
        self.assertEqual(response.status, 403)

    async def test_unicode_token_is_rejected_without_server_error(self):
        response = await self.client.post('/api/auth', json={'token': 'é🚲'}, headers={'Origin': self.origin})
        self.assertEqual(response.status, 403)

    async def test_concurrent_voice_requests_start_only_one_recorder_and_stop_it(self):
        class Recorder:
            def __init__(self):
                self.stdout = asyncio.StreamReader()
                self.returncode = None
                self.done = asyncio.Event()
            def terminate(self):
                self.returncode = 0
                self.stdout.feed_eof()
                self.done.set()
            async def wait(self):
                await self.done.wait()
                return self.returncode
        processes = []
        async def launch(*args, **kwargs):
            await asyncio.sleep(0)
            process = Recorder()
            processes.append(process)
            return process
        voice = self.app[VOICE]
        client = AsyncMock()
        self.app[CLIENTS].add(client)
        try:
            with patch.object(voice, 'paths', return_value=(Path(__file__),)*3), patch('macos.companion.asyncio.create_subprocess_exec', side_effect=launch):
                await asyncio.gather(voice.start(), voice.start())
                self.assertEqual(len(processes), 1)
                await asyncio.gather(voice.stop(), voice.stop())
                self.assertEqual(processes[0].returncode, 0)
                self.assertIsNone(voice.process)
        finally:
            for process in processes:
                if process.returncode is None: process.terminate()
            self.app[CLIENTS].discard(client)

    async def test_binary_desktop_stream_round_trip_and_cleanup(self):
        async def vnc(reader, writer):
            try:
                writer.write(b'RFB 003.008\n'); await writer.drain()
                data = await reader.readexactly(4)
                writer.write(data); await writer.drain()
            finally:
                writer.close(); await writer.wait_closed()
        server = await asyncio.start_server(vnc, '127.0.0.1', 0)
        port = server.sockets[0].getsockname()[1]
        original = asyncio.open_connection
        async def redirected(host, requested_port):
            self.assertEqual((host, requested_port), ('127.0.0.1', 5900))
            return await original(host, port)
        try:
            await self.authenticate()
            with patch('macos.companion.asyncio.open_connection', side_effect=redirected):
                ws = await self.client.ws_connect('/vnc', protocols=('binary',), headers={'Origin': self.origin})
                self.assertEqual((await ws.receive(timeout=2)).data, b'RFB 003.008\n')
                await ws.send_bytes(b'\x00\xff\x80\x01')
                self.assertEqual((await ws.receive(timeout=2)).data, b'\x00\xff\x80\x01')
                await ws.close()
        finally:
            server.close(); await server.wait_closed()


if __name__ == '__main__':
    unittest.main()
