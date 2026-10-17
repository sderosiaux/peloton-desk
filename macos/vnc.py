"""Transcode the Mac's lossless VNC pixels to browser-decoded JPEG in memory.

Used only with the paired FastDesktop client (RFB 3.8, VNCAuth, RGBX pixels).
Authentication and input still go to macOS; no password or screen is stored.
The unmodified /vnc path remains available for exact, lossless rendering.
"""
import asyncio
import io
import struct
import zlib

from PIL import Image, ImageChops

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


class ClientUpdates:
    """Observe refresh requests without changing authentication or user input."""
    def __init__(self):
        self.buffer = bytearray()
        self.skip = 30  # version(12), VNCAuth choice(1), response(16), ClientInit(1)
        self.generation = 0
        self.enabled = True

    def feed(self, data):
        if not self.enabled: return
        if self.skip:
            count = min(self.skip, len(data))
            self.skip -= count
            data = data[count:]
        self.buffer.extend(data)
        while self.buffer:
            kind = self.buffer[0]
            fixed = {0: 20, 3: 10, 4: 8, 5: 6}
            if kind in fixed:
                length = fixed[kind]
            elif kind == 2:
                if len(self.buffer) < 4: return
                length = 4 + 4 * struct.unpack('>H', self.buffer[2:4])[0]
            elif kind == 6:
                if len(self.buffer) < 8: return
                length = 8 + struct.unpack('>I', self.buffer[4:8])[0]
                if length > 1_048_584:
                    self.enabled = False; self.buffer.clear(); return
            else:
                # Unknown extensions disable deduplication, never the desktop.
                self.enabled = False; self.buffer.clear(); return
            if len(self.buffer) < length: return
            if kind == 3 and self.buffer[1] == 0:
                self.generation += 1
            del self.buffer[:length]


class FrameEncoder:
    def __init__(self, size=None):
        self.inflater = zlib.decompressobj()
        self.frame = self.valid = None
        if size: self.resize(*size)

    def resize(self, width, height):
        if not 0 < width * height <= MAX_PIXELS:
            raise ProtocolError('Invalid framebuffer size')
        self.frame = Image.new('RGB', (width, height))
        self.valid = Image.new('L', (width, height))

    def invalidate(self):
        if self.valid: self.valid.paste(0, (0, 0, *self.valid.size))

    def decode(self, header, payload):
        _, _, width, height, encoding = struct.unpack('>HHHHi', header)
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
        return Image.frombytes('RGB', (width, height), pixels, 'raw', 'RGBX')

    def packet(self, image, x, y):
        width, height = image.size
        def header(encoding): return struct.pack('>HHHHi', x, y, width, height, encoding)
        extrema = image.getextrema()
        if all(low == high for low, high in extrema):
            # Tight Fill: a blinking caret or cleared terminal area costs just
            # one RGB color, with no PNG decoder or loss of text sharpness.
            return header(7) + b'\x80' + bytes(low for low, _ in extrema)
        if width * height <= 256:
            return header(0) + image.tobytes('raw', 'RGBX')
        output = io.BytesIO()
        image.save(output, 'PNG', compress_level=3)
        png = output.getvalue()
        # Terminal lines and sparse updates stay exact; photos/full screens can
        # use JPEG. Both formats use one native browser decode per changed region.
        if width * height > 262144 or len(png) > 0x3fffff:
            output = io.BytesIO()
            image.save(output, 'JPEG', quality=70, subsampling=0)
            jpeg = output.getvalue()
            if len(jpeg) < len(png) or len(png) > 0x3fffff:
                return header(21) + jpeg
        return header(-260) + b'\xa0' + tight_length(len(png)) + png

    def encode(self, header, payload):
        x, y = struct.unpack('>HH', header[:4])
        return self.packet(self.decode(header, payload), x, y)

    def check_box(self, box):
        if self.frame is None or min(box) < 0 or box[2] > self.frame.width or box[3] > self.frame.height:
            raise ProtocolError('Rectangle outside framebuffer')

    def copy(self, header, source):
        x, y, width, height, _ = struct.unpack('>HHHHi', header)
        sx, sy = struct.unpack('>HH', source)
        destination, original = (x, y, x + width, y + height), (sx, sy, sx + width, sy + height)
        self.check_box(destination); self.check_box(original)
        self.frame.paste(self.frame.crop(original), destination)
        self.valid.paste(self.valid.crop(original), destination)

    @staticmethod
    def regions(diff, bounds):
        left, top, right, bottom = bounds
        if (right - left) * (bottom - top) <= 65536: return [bounds]
        # Merge neighboring dirty tiles to limit canvas work, but do not send
        # the entire gap between a blinking caret and a clock across the screen.
        regions, previous = [], {}
        for y in range(top, bottom, 128):
            runs, start = [], None
            for x in range(left, right, 128):
                dirty = diff.crop((x, y, min(x+128, right), min(y+128, bottom))).getbbox() is not None
                if dirty and start is None: start = x
                if not dirty and start is not None: runs.append((start, x)); start = None
            if start is not None: runs.append((start, right))
            current = {}
            for a, b in runs:
                if (a, b) in previous:
                    region = previous[(a, b)]; region[3] = min(y+128, bottom)
                else:
                    region = [a, y, b, min(y+128, bottom)]; regions.append(region)
                current[(a, b)] = region
            previous = current
            if len(regions) > 96: return [bounds]
        tight = []
        for x, y, r, b in regions:
            box = diff.crop((x, y, r, b)).getbbox()
            if box: tight.append((x+box[0], y+box[1], x+box[2], y+box[3]))
        return tight

    def update(self, header, payload):
        x, y, width, height, _ = struct.unpack('>HHHHi', header)
        box = (x, y, x+width, y+height)
        self.check_box(box)
        image = self.decode(header, payload)
        if self.valid.crop(box).getextrema() != (255, 255):
            regions = [(0, 0, width, height)]
        else:
            diff = ImageChops.difference(image, self.frame.crop(box))
            bounds = diff.getbbox()
            regions = self.regions(diff, bounds) if bounds else []
        self.frame.paste(image, box); self.valid.paste(255, box)
        return [self.packet(image.crop(region), x+region[0], y+region[1]) for region in regions]

async def send_chunks(ws, data):
    for offset in range(0, len(data), 65536):
        await ws.send_bytes(data[offset:offset + 65536])


async def fast_desktop(reader, ws, client=None):
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
    encoder = FrameEncoder(struct.unpack('>HH', initial[:4]))
    generation = -1
    while True:
        kind = (await reader.readexactly(1))[0]
        if kind == 0:
            update = await reader.readexactly(3)
            if client is not None and (not client.enabled or client.generation != generation):
                encoder.invalidate(); generation = client.generation
            converted_update = []
            converted_size = 0
            rectangles = struct.unpack('>H', update[1:])[0]
            for _ in range(rectangles):
                header = await reader.readexactly(12)
                _, _, width, height, encoding = struct.unpack('>HHHHi', header)
                if width * height > MAX_PIXELS:
                    raise ProtocolError('Framebuffer too large')
                if encoding in (0, 6):
                    length = await size32() if encoding == 6 else width * height * 4
                    payload = await reader.readexactly(length)
                    packets = await asyncio.to_thread(encoder.update, header, payload)
                    converted_update.extend(packets)
                    converted_size += sum(map(len, packets))
                elif encoding == 1:  # CopyRect
                    source = await reader.readexactly(4)
                    encoder.copy(header, source)
                    converted_update.append(header + source)
                    converted_size += 16
                elif encoding == -239:  # Rich cursor + one-bit transparency mask.
                    length = width * height * 4 + ((width + 7) // 8) * height
                    converted_update.append(header + await reader.readexactly(length))
                    converted_size += 12 + length
                elif encoding in (-223, -224):  # DesktopSize, LastRect
                    if encoding == -223:
                        encoder.resize(width, height)
                        converted_update.append(header)
                        converted_size += 12
                    if encoding == -224:
                        break
                else:
                    raise ProtocolError('Unexpected framebuffer encoding')
                if converted_size > MAX_PAYLOAD or len(converted_update) > 65534:
                    raise ProtocolError('Converted update too large')
            # Batch small rectangles into the same WebSocket message instead
            # of flushing the header and every caret/tile separately over ADB.
            await send_chunks(ws, struct.pack('>BBH', 0, 0, len(converted_update)) + b''.join(converted_update))
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
