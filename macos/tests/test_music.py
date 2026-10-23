import asyncio
import unittest
from unittest.mock import patch

from aiohttp import CookieJar, WSServerHandshakeError
from aiohttp.test_utils import TestClient, TestServer, unused_port
from macos.companion import create_app, MUSIC, TOKEN
from macos.music import Music


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


class MusicTests(unittest.IsolatedAsyncioTestCase):
    async def test_shared_capture_stops_with_last_listener_and_no_audio_is_buffered(self):
        music, processes = Music(), []
        async def launch(*args, **kwargs):
            self.assertEqual(args[-1], '--music')
            process = Recorder(); processes.append(process); return process
        with patch('macos.music.asyncio.create_subprocess_exec', side_effect=launch):
            a,b = await asyncio.gather(music.subscribe(),music.subscribe())
            self.assertEqual(len(processes),1)
            for i in range(1000): music.publish({'type':'music-frame','sequence':i})
            self.assertEqual(a.qsize(),1)
            self.assertEqual((await a.get())['sequence'],999)
            await music.unsubscribe(a)
            self.assertIsNone(processes[0].returncode)
            await music.unsubscribe(b)
            self.assertEqual(processes[0].returncode,0)
            self.assertIsNone(music.process)
            self.assertEqual(music.state['phase'],'idle')

    async def test_native_exit_reports_error_and_retry_creates_a_new_capture(self):
        music, processes = Music(), []
        async def launch(*args, **kwargs):
            process=Recorder();processes.append(process);return process
        with patch('macos.music.asyncio.create_subprocess_exec',side_effect=launch):
            a=await music.subscribe()
            processes[0].terminate();await music.reader
            self.assertEqual(music.state['phase'],'error')
            b=await music.subscribe()
            self.assertEqual(len(processes),2)
            await music.unsubscribe(a);await music.unsubscribe(b)

    async def test_music_socket_requires_session_and_same_origin_before_starting(self):
        port=unused_port();origin=f'http://127.0.0.1:{port}'
        app=create_app('fixture-token',origin)
        client=TestClient(TestServer(app,port=port),cookie_jar=CookieJar(unsafe=True))
        await client.start_server()
        try:
            with self.assertRaises(WSServerHandshakeError) as error:
                await client.ws_connect('/music',headers={'Origin':origin})
            self.assertEqual(error.exception.status,401)
            await client.post('/api/auth',json={'token':app[TOKEN]},headers={'Origin':origin})
            with self.assertRaises(WSServerHandshakeError) as error:
                await client.ws_connect('/music',headers={'Origin':'https://other.example'})
            self.assertEqual(error.exception.status,403)
            self.assertIsNone(app[MUSIC].process)
            process=Recorder()
            async def launch(*args,**kwargs): return process
            with patch('macos.music.asyncio.create_subprocess_exec',side_effect=launch):
                ws=await client.ws_connect('/music',headers={'Origin':origin})
                self.assertEqual((await ws.receive_json(timeout=2))['phase'],'starting')
                process.stdout.feed_data(b'{"type":"music-frame","energy":0.5}\n')
                self.assertEqual((await ws.receive_json(timeout=2))['energy'],.5)
                await ws.close()
                await asyncio.wait_for(process.wait(),2)
                self.assertEqual(process.returncode,0)
        finally:
            await client.close()
