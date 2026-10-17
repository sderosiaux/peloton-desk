"""Transcode the Mac's lossless VNC pixels to browser-decoded JPEG in memory.

Used only with the paired FastDesktop client (RFB 3.8, VNCAuth, RGBX pixels).
Authentication and input still go to macOS; no password or screen is stored.
The unmodified /vnc path remains available for exact, lossless rendering.
"""
import asyncio
import io
import struct
import zlib

from PIL import Image

MAX_PIXELS = 16_777_216
MAX_PAYLOAD = MAX_PIXELS * 4


class ProtocolError(ValueError):
    pass


def tight_length(length):
    if not 0 <= length <= 0x3fffff:
        raise ProtocolError('Tight image too large')
    data = bytearray((length & 0x7f,))
    if length > 0x7f:
        data[0] |= 0x80
        data.append((length >> 7) & 0x7f)
        if length > 0x3fff:
            data[1] |= 0x80
            data.append(length >> 14)
    return bytes(data)


class FrameEncoder:
    def __init__(self):
        self.inflater = zlib.decompressobj()

    def encode(self, header, payload):
        x, y, width, height, encoding = struct.unpack('>HHHHi', header)
        expected = width * height * 4
        if not expected or expected > MAX_PAYLOAD:
            raise ProtocolError('Invalid framebuffer size')
        if encoding == 6:
            try:
                pixels = self.inflater.decompress(payload, expected + 1)
            except zlib.error as exc:
                raise ProtocolError('Invalid compressed framebuffer') from exc
            if self.inflater.unconsumed_tail or self.inflater.unused_data:
                raise ProtocolError('Invalid compressed framebuffer')
        else:
            pixels = payload
        if len(pixels) != expected:
            raise ProtocolError('Invalid pixel count')
        # Small changes (caret, letters) stay exact and avoid JPEG overhead.
        if width * height <= 4096:
            return struct.pack('>HHHHi', x, y, width, height, 0) + pixels
        image = Image.frombytes('RGB', (width, height), pixels, 'raw', 'RGBX')
        output = io.BytesIO()
        image.save(output, 'JPEG', quality=70, subsampling=0)
        jpeg = output.getvalue()
        # Flat panels and small text can compress better losslessly. PNG also
        # uses the browser's native decoder, without thousands of canvas tiles.
        if encoding == 6 and len(payload) < len(jpeg):
            output = io.BytesIO()
            image.save(output, 'PNG', compress_level=3)
            png = output.getvalue()
            if len(png) < len(jpeg) and len(png) <= 0x3fffff:
                return struct.pack('>HHHHi', x, y, width, height, -260) + b'\xa0' + tight_length(len(png)) + png
        # RFB encoding 21 is a complete JPEG stream, with no length prefix.
        return struct.pack('>HHHHi', x, y, width, height, 21) + jpeg


async def send_chunks(ws, data):
    for offset in range(0, len(data), 65536):
        await ws.send_bytes(data[offset:offset + 65536])


async def fast_desktop(reader, ws):
    async def relay(count):
        data = await reader.readexactly(count)
        await send_chunks(ws, data)
        return data

    async def size32(limit=MAX_PAYLOAD):
        size = struct.unpack('>I', await reader.readexactly(4))[0]
        if size > limit:
            raise ProtocolError('RFB payload too large')
        return size

    # The app always replies RFB 3.8 and selects the dedicated VNC password.
    banner = await reader.readexactly(12)
    if banner not in (b'RFB 003.008\n', b'RFB 003.889\n'):
        raise ProtocolError('Unsupported VNC version')
    await ws.send_bytes(b'RFB 003.008\n')
    count = (await reader.readexactly(1))[0]
    if count == 0:
        raise ProtocolError('VNC authentication unavailable')
    methods = await reader.readexactly(count)
    if 2 not in methods:
        raise ProtocolError('VNC password authentication unavailable')
    await ws.send_bytes(bytes((1, 2)))
    await relay(16)  # Challenge, forwarded without inspecting credentials.
    result = await relay(4)
    if result != bytes(4):
        length = await size32(65536)
        await ws.send_bytes(struct.pack('>I', length))
        await relay(length)
        return
    initial = await relay(24)
    name_length = struct.unpack('>I', initial[20:24])[0]
    if name_length > 65536:
        raise ProtocolError('VNC name too large')
    await relay(name_length)
    encoder = FrameEncoder()
    while True:
        kind = (await reader.readexactly(1))[0]
        if kind == 0:
            update = await reader.readexactly(3)
            await ws.send_bytes(bytes((kind,)) + update)
            rectangles = struct.unpack('>H', update[1:])[0]
            for _ in range(rectangles):
                header = await reader.readexactly(12)
                _, _, width, height, encoding = struct.unpack('>HHHHi', header)
                if width * height > MAX_PIXELS:
                    raise ProtocolError('Framebuffer too large')
                if encoding in (0, 6):
                    length = await size32() if encoding == 6 else width * height * 4
                    payload = await reader.readexactly(length)
                    converted = await asyncio.to_thread(encoder.encode, header, payload)
                    await send_chunks(ws, converted)
                elif encoding == 1:  # CopyRect
                    await ws.send_bytes(header + await reader.readexactly(4))
                elif encoding == -239:  # Rich cursor + one-bit transparency mask.
                    length = width * height * 4 + ((width + 7) // 8) * height
                    await send_chunks(ws, header + await reader.readexactly(length))
                elif encoding in (-223, -224):  # DesktopSize, LastRect
                    await ws.send_bytes(header)
                    if encoding == -224:
                        break
                else:
                    raise ProtocolError('Unexpected framebuffer encoding')
        elif kind == 2:  # Bell
            await ws.send_bytes(bytes((kind,)))
        elif kind == 3:  # ServerCutText
            header = await reader.readexactly(7)
            length = struct.unpack('>I', header[3:])[0]
            if length > 1_048_576:
                raise ProtocolError('Clipboard payload too large')
            await send_chunks(ws, bytes((kind,)) + header + await reader.readexactly(length))
        elif kind == 1:  # SetColourMapEntries (not used by our true-color client).
            header = await reader.readexactly(5)
            length = struct.unpack('>H', header[3:])[0] * 6
            await send_chunks(ws, bytes((kind,)) + header + await reader.readexactly(length))
        else:
            raise ProtocolError('Unexpected VNC server message')
