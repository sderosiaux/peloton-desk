"""Loopback-only gateway. ADB's paired TLS transport carries it to the Bike."""
import argparse
import asyncio
import contextlib
import hmac
import json
import os
import shutil
import signal
from collections import deque
import sys
import time
from pathlib import Path

from aiohttp import web, WSMsgType

try:
    from .vnc import fast_desktop, ProtocolError, ClientUpdates
    from .music import Music
except ImportError:  # Direct execution by the native companion.
    from vnc import fast_desktop, ProtocolError, ClientUpdates
    from music import Music

ROOT = Path(__file__).resolve().parents[1]
PORT = 8765
TOKEN = web.AppKey('token', str)
ORIGIN = web.AppKey('origin', str)
CLIENTS = web.AppKey('clients', set)
SOCKETS = web.AppKey('sockets', set)
MUSIC = web.AppKey('music', Music)


class Voice:
    def __init__(self, app):
        self.app, self.process, self.reader = app, None, None
        self.lifecycle = asyncio.Lock()
        self.source = 'bike'
        self.state = {'type': 'voice-state', 'active': False, 'phase': 'idle'}
        self.history = deque(maxlen=20)
        self.sequence = 0
        self.finisher = None
        self.cancel_start = False

    def config(self):
        config_path = ROOT / '.local/voice.json'
        return json.loads(config_path.read_text()) if config_path.exists() else {}

    def paths(self):
        config = self.config()
        engine = config.get('worker') if config.get('engine') == 'parakeet' else config.get('whisper')
        return (Path(os.environ.get('PELOTON_DESK_HELPER', ROOT / '.local/Peloton Desk Mac.app/Contents/MacOS/PelotonDesk')),
                Path(engine or shutil.which('whisper-cli') or '/opt/homebrew/bin/whisper-cli'),
                Path(config.get('model', ROOT / '.local/models/ggml-base.bin')))

    async def emit(self, event):
        if event['type'] == 'voice-state':
            self.state = event
        if event['type'] == 'transcription':
            self.sequence += 1
            event = dict(event, id=self.sequence, at=time.time())
            self.history.append(event)
            asyncio.get_running_loop().call_later(600, self.expire_history)
        if event['type'] not in ('audio-level', 'transcription-preview'):
            # Deliberately omit transcript, audio, paths and credentials from disk logs.
            record = {key: event[key] for key in ('type', 'phase', 'active', 'targetFound', 'targetMode', 'inserted', 'enterPosted', 'deliveryReason', 'sendReturn', 'audioSeconds', 'elapsedMs', 'characters', 'code') if key in event}
            record['at'] = time.time()
            if 'text' in event: record['characters'] = len(event['text'])
            print(json.dumps(record, ensure_ascii=False), flush=True)
        for client in tuple(self.app[CLIENTS]):
            with contextlib.suppress(ConnectionError, RuntimeError):
                await client.send_json(event)

    def expire_history(self):
        while self.history and time.time() - self.history[0]['at'] >= 600:
            self.history.popleft()

    async def start(self, source='bike', send_return=False):
        async with self.lifecycle:
            if self.process and self.source != source:
                raise web.HTTPConflict(text=json.dumps({'error': 'La dictée est déjà utilisée sur l’autre écran.'}), content_type='application/json')
            self.source = source
            self.cancel_start = False
            try:
                await self._start(send_return=send_return)
            except Exception:
                await self.emit({'type': 'voice-state', 'active': False, 'phase': 'idle'})
                raise

    async def _start(self, send_return=False):
        if self.process and self.process.returncode is None:
            return
        binary, whisper, model = self.paths()
        if not all(p.exists() for p in (binary, whisper, model)):
            raise web.HTTPConflict(text=json.dumps({'error': 'Le moteur de dictée locale doit encore être installé sur le Mac.'}), content_type='application/json')
        if not self.app[CLIENTS]:
            raise web.HTTPConflict(text=json.dumps({'error': 'Reconnectez Peloton Desk avant d’activer le micro.'}), content_type='application/json')
        await self.emit({'type': 'voice-state', 'active': False, 'phase': 'starting'})
        parent = int(os.environ.get('PELOTON_DESK_APP_PID', '0'))
        if parent and parent == os.getppid():
            # The menu app owns the permission prompt and status snapshot.
            os.kill(parent, signal.SIGUSR2)
            for _ in range(150):
                if self.cancel_start: return
                try:
                    permissions = json.loads((ROOT / '.local/permissions.json').read_text())
                    microphone = permissions['microphone']
                    if microphone == 'authorized': break
                    if microphone in ('denied', 'restricted'):
                        raise web.HTTPConflict(text=json.dumps({'error': 'Autorisez le micro pour Peloton Desk Mac dans les réglages macOS.'}), content_type='application/json')
                except (OSError, ValueError, KeyError): pass
                await asyncio.sleep(0.2)
            else:
                raise web.HTTPConflict(text=json.dumps({'error': 'Terminez la demande d’autorisation du micro sur le Mac, puis réessayez.'}), content_type='application/json')
        arguments = [str(binary), '--voice-parakeet' if self.config().get('engine') == 'parakeet' else '--voice', str(whisper), str(model)]
        if send_return is True: arguments.append('--send-return')
        self.process = await asyncio.create_subprocess_exec(*arguments, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        self.reader = asyncio.create_task(self.read_events(self.process))

    async def read_events(self, process):
        try:
            async for line in process.stdout:
                try:
                    event = json.loads(line)
                    if not isinstance(event, dict) or 'type' not in event: continue
                    await self.emit(event)
                except (ValueError, UnicodeDecodeError):
                    continue
            await process.wait()
        finally:
            if self.process is process:
                self.process = None
            await self.emit({'type': 'voice-state', 'active': False, 'phase': 'idle'})

    async def finish(self):
        async with self.lifecycle:
            process = self.process
            if process and process.returncode is None:
                with contextlib.suppress(ProcessLookupError): process.send_signal(signal.SIGUSR1)
                if not self.finisher or self.finisher.done():
                    self.finisher = asyncio.create_task(self.finish_timeout(process))

    async def finish_timeout(self, process):
        try:
            await asyncio.wait_for(asyncio.shield(process.wait()), 60)
        except asyncio.TimeoutError:
            await self.emit({'type': 'error', 'message': 'La fin de transcription a dépassé le délai. Réessayez une phrase plus courte.'})
            if self.process is process: await self.stop()

    async def stop(self):
        self.cancel_start = True
        async with self.lifecycle:
            await self._stop()
            await self.emit({'type': 'voice-state', 'active': False, 'phase': 'idle'})

    async def _stop(self):
        if self.finisher and self.finisher is not asyncio.current_task():
            self.finisher.cancel()
            self.finisher = None
        process = self.process
        if process and process.returncode is None:
            with contextlib.suppress(ProcessLookupError):
                process.terminate()
            try:
                await asyncio.wait_for(process.wait(), 3)
            except asyncio.TimeoutError:
                with contextlib.suppress(ProcessLookupError):
                    process.kill()
                await process.wait()
        if self.reader:
            with contextlib.suppress(asyncio.CancelledError):
                await self.reader
            self.reader = None


VOICE = web.AppKey('voice', Voice)


def authenticated(request):
    return hmac.compare_digest(request.cookies.get('desk_session', ''), request.app[TOKEN])


@web.middleware
async def guard(request, handler):
    if request.host != request.app[ORIGIN].removeprefix('http://'):
        return web.json_response({'error': 'Hôte refusé.'}, status=403)
    sensitive = request.path.startswith('/api/') or request.path in ('/vnc', '/events', '/music')
    if (sensitive and request.method != 'GET') or request.path in ('/vnc', '/events', '/music'):
        if request.headers.get('Origin') != request.app[ORIGIN]:
            return web.json_response({'error': 'Origine refusée.'}, status=403)
    if sensitive and request.path != '/api/auth' and not authenticated(request):
        return web.json_response({'error': 'Ouvrez Peloton Desk depuis son lanceur sur le Mac.'}, status=401)
    return await handler(request)


async def auth(request):
    try:
        data = await request.json()
        token = data.get('token', '')
        valid = isinstance(token, str) and hmac.compare_digest(token.encode(), request.app[TOKEN].encode())
    except (ValueError, AttributeError):
        valid = False
    if not valid:
        return web.json_response({'error': 'Connexion au compagnon non autorisée.'}, status=403)
    response = web.json_response({'ok': True})
    response.set_cookie('desk_session', request.app[TOKEN], httponly=True, samesite='Strict')
    return response


def voice_readiness(ready, permissions_path=ROOT / '.local/permissions.json'):
    if not ready:
        return False, 'Moteur de dictée locale à installer sur le Mac.'
    try:
        permissions = json.loads(permissions_path.read_text())
        age = time.time() - permissions['updatedAt']
        if not 0 <= age < 30:
            raise ValueError('stale')
        microphone = permissions['microphone'] == 'authorized'
        accessibility = permissions['accessibility'] is True
    except (OSError, ValueError, TypeError, KeyError):
        return False, 'Ouvrez le compagnon Mac pour vérifier les autorisations de dictée.'
    if microphone and accessibility:
        return True, 'Dictée locale prête · micro et accessibilité autorisés.'
    missing = 'le micro et l’accessibilité' if not microphone and not accessibility else 'le micro' if not microphone else 'l’accessibilité'
    return False, f'Sur le Mac, menu vélo → autoriser {missing} pour la dictée.'


async def status(request):
    available = False
    try:
        _, writer = await asyncio.wait_for(asyncio.open_connection('127.0.0.1', 5900), 1)
        writer.close()
        await writer.wait_closed()
        available = True
    except (OSError, asyncio.TimeoutError):
        pass
    ready = all(p.exists() for p in request.app[VOICE].paths())
    voice_ready, detail = voice_readiness(ready)
    model_name = 'Parakeet V3' if request.app[VOICE].config().get('engine') == 'parakeet' else 'Whisper ' + request.app[VOICE].paths()[2].stem.removeprefix('ggml-')
    return web.json_response({'vncAvailable': available, 'voiceReady': voice_ready, 'voiceDetail': detail, 'voiceModel': model_name,
                             'voiceAutoSend': request.app[VOICE].config().get('sendReturn') is True})


async def proxy(request):
    try:
        reader, writer = await asyncio.wait_for(asyncio.open_connection('127.0.0.1', 5900), 3)
    except (OSError, asyncio.TimeoutError):
        raise web.HTTPServiceUnavailable(text='Activez le partage d’écran du Mac.')
    ws = web.WebSocketResponse(protocols=('binary',), max_msg_size=8*1024*1024, heartbeat=20)
    await ws.prepare(request)
    request.app[SOCKETS].add(ws)
    client_updates = ClientUpdates()

    async def upstream():
        async for message in ws:
            if message.type == WSMsgType.BINARY:
                client_updates.feed(message.data)
                writer.write(message.data)
                await writer.drain()
            elif message.type == WSMsgType.ERROR:
                break

    async def downstream():
        if request.query.get('mode') == 'fast':
            await fast_desktop(reader, ws, client_updates)
            return
        while chunk := await reader.read(65536):
            await ws.send_bytes(chunk)

    tasks = [asyncio.create_task(upstream()), asyncio.create_task(downstream())]
    try:
        done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in done:
            try:
                task.result()
            except ProtocolError:
                await request.app[VOICE].emit({'type': 'notice', 'message': 'Bureau fluide indisponible. Dans ···, choisissez « Image exacte » puis reconnectez le bureau.'})
            except (asyncio.IncompleteReadError, ConnectionError):
                pass
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        writer.close()
        with contextlib.suppress(OSError):
            await writer.wait_closed()
        await ws.close()
        request.app[SOCKETS].discard(ws)
        if request.app[VOICE].source == 'bike':
            await request.app[VOICE].stop()
    return ws


async def events(request):
    ws = web.WebSocketResponse(heartbeat=15)
    await ws.prepare(request)
    request.app[CLIENTS].add(ws)
    request.app[SOCKETS].add(ws)
    await ws.send_json(request.app[VOICE].state)
    for event in request.app[VOICE].history:
        if time.time() - event['at'] < 600: await ws.send_json(dict(event, replayed=True))
    try:
        async for _ in ws:
            pass
    finally:
        request.app[CLIENTS].discard(ws)
        request.app[SOCKETS].discard(ws)
        if request.app[VOICE].source == request.query.get('source', 'bike'):
            await request.app[VOICE].stop()
    return ws


async def music_events(request):
    ws = web.WebSocketResponse(heartbeat=5, max_msg_size=1024)
    await ws.prepare(request)
    request.app[SOCKETS].add(ws)
    music = request.app[MUSIC]
    queue = await music.subscribe()

    async def send():
        while True:
            await asyncio.wait_for(ws.send_json(await queue.get()), 2)

    async def receive():
        async for _ in ws:
            pass

    tasks = [asyncio.create_task(send()), asyncio.create_task(receive())]
    try:
        await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        await music.unsubscribe(queue)
        request.app[SOCKETS].discard(ws)
        await ws.close()
    return ws


async def voice_start(request):
    data = await request.json()
    await request.app[VOICE].start('mac' if data.get('source') == 'mac' else 'bike', send_return=data.get('sendReturn') is True)
    return web.json_response({'ok': True})


async def voice_finish(request):
    await request.app[VOICE].finish()
    return web.json_response({'ok': True})


async def voice_history(request):
    voice = request.app[VOICE]
    return web.json_response({'state': voice.state, 'transcripts': [event for event in voice.history if time.time() - event['at'] < 600]})


async def voice_stop(request):
    data = await request.json()
    voice = request.app[VOICE]
    if not data.get('source') or data['source'] == voice.source:
        await voice.stop()
    return web.json_response({'ok': True})


async def cleanup(app):
    await app[VOICE].stop()
    await app[MUSIC].stop()
    for ws in tuple(app[SOCKETS]):
        await ws.close()


def create_app(token, origin=f'http://127.0.0.1:{PORT}'):
    app = web.Application(middlewares=[guard], client_max_size=16384)
    app[TOKEN], app[ORIGIN], app[CLIENTS], app[SOCKETS] = token, origin, set(), set()
    app[VOICE] = Voice(app)
    app[MUSIC] = Music()
    app.add_routes([web.post('/api/auth', auth), web.get('/api/status', status),
        web.get('/vnc', proxy), web.get('/events', events), web.get('/music', music_events),
        web.post('/api/voice/start', voice_start), web.post('/api/voice/stop', voice_stop),
        web.post('/api/voice/finish', voice_finish), web.get('/api/voice/history', voice_history)])
    async def index(request):
        response = web.FileResponse(ROOT / '.local/web' / ('voice.html' if request.path == '/voice.html' else 'index.html'))
        response.headers['Content-Security-Policy'] = "default-src 'self'; connect-src 'self' ws://127.0.0.1:8765; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'"
        response.headers['Cache-Control'] = 'no-store'
        return response
    app.router.add_get('/', index)
    app.router.add_get('/voice.html', index)
    app.router.add_static('/', ROOT / '.local/web', show_index=False)
    app.on_shutdown.append(cleanup)
    return app


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', required=True)
    parser.add_argument('--no-open', action='store_true')
    args = parser.parse_args()
    sys.path.insert(0, str(ROOT / 'tools'))
    from bike import connection_token, open_desktop, DeskError
    token = connection_token()
    if not args.no_open:
        try:
            open_desktop(args.serial, auto_connect=False)
        except DeskError:
            print('Bike non connecté. Utilisez le menu vélo → Ouvrir le bureau sur le Bike.', flush=True)
    print('Peloton Desk ready. Gateway bound to 127.0.0.1 only.', flush=True)
    web.run_app(create_app(token), host='127.0.0.1', port=PORT, access_log=None, print=None)


if __name__ == '__main__':
    main()
