"""One Spotify tap while at least one authenticated Focus screen is connected."""
import asyncio
import contextlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Music:
    def __init__(self):
        self.listeners = set()
        self.lock = asyncio.Lock()
        self.process = None
        self.reader = None
        self.state = self.event('idle', 'Ultra focus prêt.')

    @staticmethod
    def event(phase, detail):
        return {'type': 'music-state', 'phase': phase, 'detail': detail, 'source': 'Spotify'}

    def publish(self, event):
        if event.get('type') == 'music-state':
            self.state = event
        for queue in self.listeners:
            # Bounded latest-value delivery. A slow screen cannot stall audio capture.
            if queue.full():
                queue.get_nowait()
            queue.put_nowait(event)

    async def subscribe(self):
        queue = asyncio.Queue(maxsize=1)
        async with self.lock:
            self.listeners.add(queue)
            queue.put_nowait(self.state)
            if self.state.get('phase') == 'error':
                await self._stop()
            if self.process is None:
                binary = Path(os.environ.get('PELOTON_DESK_HELPER', ROOT / '.local/Peloton Desk Mac.app/Contents/MacOS/PelotonDesk'))
                self.publish(self.event('starting', 'Connexion au son de Spotify…'))
                try:
                    self.process = await asyncio.create_subprocess_exec(
                        str(binary), '--music', stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.DEVNULL, limit=16384)
                    self.reader = asyncio.create_task(self.read_events(self.process))
                except (OSError, ValueError):
                    self.publish(self.event('error', 'Relancez le compagnon Mac pour activer Ultra focus.'))
        return queue

    async def read_events(self, process):
        try:
            async for line in process.stdout:
                try:
                    event = json.loads(line)
                    if isinstance(event, dict) and event.get('type') in ('music-state', 'music-frame'):
                        self.publish(event)
                except (ValueError, UnicodeDecodeError):
                    pass
            await process.wait()
        finally:
            if self.process is process:
                self.process = None
                if self.listeners and self.state.get('phase') != 'error':
                    self.publish(self.event('error', 'Le son de Spotify a été interrompu. Touchez Réessayer.'))

    async def unsubscribe(self, queue):
        async with self.lock:
            self.listeners.discard(queue)
            if not self.listeners:
                await self._stop()

    async def _stop(self):
        process, reader = self.process, self.reader
        self.process = self.reader = None
        if process and process.returncode is None:
            with contextlib.suppress(ProcessLookupError):
                process.terminate()
            try:
                await asyncio.wait_for(process.wait(), 3)
            except asyncio.TimeoutError:
                with contextlib.suppress(ProcessLookupError):
                    process.kill()
                await process.wait()
        if reader:
            with contextlib.suppress(asyncio.CancelledError):
                await reader
        self.state = self.event('idle', 'Ultra focus prêt.')

    async def stop(self):
        async with self.lock:
            self.listeners.clear()
            await self._stop()
