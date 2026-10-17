import asyncio
import io
import struct
import unittest
import zlib

from PIL import Image
from macos.vnc import FrameEncoder, ProtocolError, fast_desktop


def rectangle(width, height, encoding=6):
    return struct.pack('>HHHHi', 0, 0, width, height, encoding)


def decode_image(data):
    encoding = struct.unpack('>i', data[8:12])[0]
    if encoding == 7:
        assert data[12] == 0x80 and len(data) == 16
        return Image.new('RGB',struct.unpack('>HH',data[4:8]),tuple(data[13:16]))
    if encoding == 21:
        return Image.open(io.BytesIO(data[12:]))
    if encoding == -260:
        assert data[12] == 0xa0
        offset, length = 13, 0
        for shift in (0, 7, 14):
            byte = data[offset]; offset += 1
            length |= (byte & (0xff if shift == 14 else 0x7f)) << shift
            if shift == 14 or not byte & 0x80:
                break
        assert len(data) == offset + length
        return Image.open(io.BytesIO(data[offset:]))
    raise AssertionError(f'Unexpected image encoding {encoding}')


class FrameTests(unittest.TestCase):
    def test_small_updates_and_persistent_zlib_history_are_preserved(self):
        compressor, encoder = zlib.compressobj(), FrameEncoder()
        for color in ('red', 'blue', 'green'):
            pixels = Image.new('RGB', (8, 8), color).tobytes('raw', 'RGBX')
            compressed = compressor.compress(pixels) + compressor.flush(zlib.Z_SYNC_FLUSH)
            converted = encoder.encode(rectangle(8, 8), compressed)
            self.assertEqual(len(converted),16)
            self.assertEqual(decode_image(converted).tobytes('raw','RGBX'),pixels)

    def test_small_nonuniform_updates_keep_exact_raw_pixels(self):
        image=Image.new('RGB',(8,8),'red');image.putpixel((0,0),(0,0,255))
        pixels=image.tobytes('raw','RGBX')
        self.assertEqual(FrameEncoder().encode(rectangle(8,8,0),pixels),rectangle(8,8,0)+pixels)

    def test_jpeg_preserves_dimensions_and_rgb_channel_order(self):
        image = Image.new('RGB', (160, 80), 'red')
        image.paste('blue', (80, 0, 160, 80))
        converted = FrameEncoder().encode(rectangle(160, 80, 0), image.tobytes('raw', 'RGBX'))
        decoded = decode_image(converted)
        self.assertEqual(decoded.size, image.size)
        self.assertGreater(decoded.getpixel((20, 40))[0], 240)
        self.assertGreater(decoded.getpixel((140, 40))[2], 240)

    def test_flat_screen_uses_a_single_lossless_color(self):
        image = Image.new('RGB', (320, 200), '#f5f4ef')
        compressor = zlib.compressobj()
        pixels = image.tobytes('raw', 'RGBX')
        data = compressor.compress(pixels) + compressor.flush(zlib.Z_SYNC_FLUSH)
        converted = FrameEncoder().encode(rectangle(320, 200), data)
        self.assertEqual(struct.unpack('>i', converted[8:12])[0], 7)
        self.assertEqual(len(converted),16)
        self.assertEqual(decode_image(converted).tobytes(), image.tobytes())

    def test_malformed_or_oversized_pixels_are_rejected(self):
        for header, payload in [(rectangle(65535, 65535, 0), b''),
                                (rectangle(2, 2, 0), bytes(8)),
                                (rectangle(0, 0, 0), b''),
                                (rectangle(1, 1), zlib.compress(bytes(10000)))]:
            with self.subTest(header=header), self.assertRaises(ProtocolError):
                FrameEncoder().encode(header, payload)


class RelayTests(unittest.IsolatedAsyncioTestCase):
    async def test_fragmented_authenticated_stream_and_cursor_survive_conversion(self):
        reader = asyncio.StreamReader()
        class WebSocket:
            output = bytearray()
            async def send_bytes(self, data):
                self.output.extend(data)
        ws = WebSocket()
        initial = struct.pack('>HH', 8, 8) + bytes(16) + struct.pack('>I', 4) + b'test'
        challenge = bytes(range(16))
        prefix = b'RFB 003.889\n' + bytes((3, 30, 2, 35)) + challenge + bytes(4) + initial
        pixels = Image.new('RGB', (8, 8), 'red').tobytes('raw', 'RGBX')
        compressor = zlib.compressobj()
        payload = compressor.compress(pixels) + compressor.flush(zlib.Z_SYNC_FLUSH)
        update = b'\0\0\0\x02' + rectangle(8, 8) + struct.pack('>I', len(payload)) + payload
        cursor = rectangle(1, 1, -239) + bytes((255, 0, 0, 0, 128))
        async def feed():
            for byte in prefix + update + cursor + b'\x02':
                reader.feed_data(bytes((byte,)))
                await asyncio.sleep(0)
            reader.feed_eof()
        producer = asyncio.create_task(feed())
        with self.assertRaises(asyncio.IncompleteReadError):
            await fast_desktop(reader, ws)
        await producer
        expected = b'RFB 003.008\n\x01\x02' + challenge + bytes(4) + initial
        expected += b'\0\0\0\x02' + rectangle(8, 8, 7) + b'\x80\xff\x00\x00' + cursor + b'\x02'
        self.assertEqual(bytes(ws.output), expected)

    async def test_authentication_failure_is_forwarded_without_reading_frames(self):
        reader = asyncio.StreamReader()
        reader.feed_data(b'RFB 003.008\n\x01\x02' + bytes(16) + struct.pack('>II', 1, 6) + b'denied')
        reader.feed_eof()
        class WebSocket:
            output = bytearray()
            async def send_bytes(self, data): self.output.extend(data)
        ws = WebSocket()
        await fast_desktop(reader, ws)
        self.assertTrue(ws.output.endswith(struct.pack('>II', 1, 6) + b'denied'))


if __name__ == '__main__':
    unittest.main()

class DeltaTests(unittest.TestCase):
    def setUp(self):
        self.encoder = FrameEncoder((1024, 768))
        self.screen = Image.new('RGB', (1024, 768), '#202622')
        self.header = rectangle(1024, 768, 0)
        self.encoder.update(self.header, self.screen.tobytes('raw', 'RGBX'))

    def update(self):
        return self.encoder.update(self.header, self.screen.tobytes('raw', 'RGBX'))

    def test_identical_full_frame_sends_no_pixels(self):
        self.assertEqual(self.update(), [])

    def test_far_apart_changes_do_not_resend_the_gap(self):
        self.screen.paste('white', (20, 100, 30, 120))
        self.screen.paste('red', (900, 600, 910, 620))
        packets = self.update()
        self.assertEqual(len(packets), 2)
        self.assertLess(sum(map(len, packets)), 2000)
        self.assertEqual([struct.unpack('>HHHH', p[:8]) for p in packets], [(20, 100, 10, 20), (900, 600, 10, 20)])
        self.assertEqual(self.update(), [])

    def test_changed_terminal_region_is_lossless(self):
        self.screen.paste('white', (20, 100, 420, 124))
        packet, = self.update()
        self.assertEqual(struct.unpack('>i', packet[8:12])[0], 7)
        self.assertEqual(decode_image(packet).tobytes(), self.screen.crop((20, 100, 420, 124)).tobytes())

    def test_copyrect_updates_cache_even_for_overlapping_scroll(self):
        self.screen.paste('white', (0, 0, 1024, 10)); self.update()
        header = struct.pack('>HHHHi', 0, 10, 1024, 758, 1)
        self.encoder.copy(header, struct.pack('>HH', 0, 0))
        self.screen.paste(self.screen.crop((0, 0, 1024, 758)), (0, 10))
        self.assertEqual(self.update(), [])

    def test_unknown_black_pixels_and_forced_refresh_are_sent(self):
        encoder = FrameEncoder((100, 100))
        packet = rectangle(10, 10, 0)
        black = Image.new('RGB', (10, 10)).tobytes('raw', 'RGBX')
        self.assertEqual(len(encoder.update(packet, black)), 1)
        self.assertEqual(encoder.update(packet, black), [])
        encoder.invalidate()
        self.assertEqual(len(encoder.update(packet, black)), 1)
        encoder.resize(100, 100)
        self.assertEqual(len(encoder.update(packet, black)), 1)

    def test_out_of_bounds_rectangles_are_rejected(self):
        with self.assertRaises(ProtocolError):
            self.encoder.update(struct.pack('>HHHHi', 1020, 0, 10, 10, 0), bytes(400))
        with self.assertRaises(ProtocolError):
            self.encoder.copy(rectangle(10, 10, 1), struct.pack('>HH', 1020, 0))


class ClientUpdateTests(unittest.TestCase):
    def test_fragmented_handshake_input_and_refresh_tracking(self):
        from macos.vnc import ClientUpdates
        tracker = ClientUpdates()
        messages = bytes(30) + struct.pack('>BBHii', 2, 0, 2, 6, 1)
        messages += struct.pack('>BBHHHH', 3, 0, 0, 0, 1024, 768)
        messages += struct.pack('>BBHHHH', 3, 1, 0, 0, 1024, 768)
        messages += b'\x05\x00\x00\x00\x00\x00'
        messages += b'\x06\x00\x00\x00' + struct.pack('>I', 3) + b'abc'
        for byte in messages: tracker.feed(bytes((byte,)))
        self.assertTrue(tracker.enabled)
        self.assertEqual(tracker.generation, 1)
        self.assertEqual(tracker.buffer, b'')
        tracker.feed(b'\xff')
        self.assertFalse(tracker.enabled)
