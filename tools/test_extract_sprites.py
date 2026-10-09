"""Run: python3 -m unittest discover tools"""

import struct
import unittest
import zlib

from PIL import Image

from extract_sprites import SpriteError, build_sheet, exported_sprite_names, frame_bounds, parse_origin, sheet_columns

DEFINE_SPRITE = 39
SYMBOL_CLASS = 76
END = 0


def tag(code: int, body: bytes) -> bytes:
    if len(body) < 63:
        return struct.pack('<H', (code << 6) | len(body)) + body
    return struct.pack('<HI', (code << 6) | 63, len(body)) + body


def define_sprite(sprite_id: int) -> bytes:
    return tag(DEFINE_SPRITE, struct.pack('<HH', sprite_id, 1) + tag(END, b''))


def symbol_class(symbols: dict) -> bytes:
    body = struct.pack('<H', len(symbols))
    for symbol_id, name in symbols.items():
        body += struct.pack('<H', symbol_id) + name.encode() + b'\0'
    return tag(SYMBOL_CLASS, body)


def swf(tags: bytes, compressed: bool = False) -> bytes:
    # empty RECT (1 byte), frame rate, frame count
    body = b'\x00' + struct.pack('<HH', 25 << 8, 1) + tags + tag(END, b'')
    header = (b'CWS' if compressed else b'FWS') + b'\x09' + struct.pack('<I', len(body) + 8)
    return header + (zlib.compress(body) if compressed else body)


class ExportedSpriteNamesTest(unittest.TestCase):
    def test_maps_sprite_ids_to_class_names(self):
        data = swf(define_sprite(5) + define_sprite(9) + symbol_class({5: 'Table', 9: 'Chair02'}))

        self.assertEqual(exported_sprite_names(data), {5: 'Table', 9: 'Chair02'})

    def test_reads_compressed_swf(self):
        data = swf(define_sprite(5) + symbol_class({5: 'Table'}), compressed=True)

        self.assertEqual(exported_sprite_names(data), {5: 'Table'})

    def test_skips_timeline_internal_classes_and_non_sprites(self):
        data = swf(define_sprite(5) + symbol_class({5: 'indoor_asset_fla.DoorAnim_846', 7: 'SomeBitmap', 0: 'Main'}))

        self.assertEqual(exported_sprite_names(data), {})

    def test_reads_tags_with_long_headers(self):
        long_name = 'A' * 80
        data = swf(define_sprite(5) + symbol_class({5: long_name}))

        self.assertEqual(exported_sprite_names(data), {5: long_name})

    def test_rejects_data_that_is_not_a_swf(self):
        with self.assertRaises(SpriteError):
            exported_sprite_names(b'PNG\x00not a swf')


class ParseOriginTest(unittest.TestCase):
    def test_reads_translation_of_the_root_group(self):
        svg = '<svg height="63.5px" width="80.0px"><g transform="matrix(1.0, 0.0, 0.0, 1.0, 40.0, 24.5)"><use/></g></svg>'

        self.assertEqual(parse_origin(svg, 'Table'), (40.0, 24.5))

    def test_reads_negative_offsets(self):
        svg = '<svg><g transform="matrix(1.0, 0.0, 0.0, 1.0, 40.4, -0.8)"></g></svg>'

        self.assertEqual(parse_origin(svg, 'FloorTile'), (40.4, -0.8))

    def test_names_the_sprite_when_there_is_no_root_transform(self):
        with self.assertRaises(SpriteError) as raised:
            parse_origin('<svg><g></g></svg>', 'Table')

        self.assertIn('Table', str(raised.exception))


class FrameBoundsTest(unittest.TestCase):
    def test_measures_the_drawn_pixels_relative_to_the_origin(self):
        frame = Image.new('RGBA', (20, 10), (0, 0, 0, 0))
        frame.paste((255, 0, 0, 255), (4, 2, 12, 9))

        self.assertEqual(frame_bounds(frame, origin=(6.0, 5.0)), [-2.0, -3.0, 6.0, 4.0])

    def test_an_empty_frame_has_no_extent(self):
        frame = Image.new('RGBA', (20, 10), (0, 0, 0, 0))

        self.assertEqual(frame_bounds(frame, origin=(6.0, 5.0)), [0.0, 0.0, 0.0, 0.0])


class SheetTest(unittest.TestCase):
    def test_columns_fill_the_maximum_width(self):
        self.assertEqual(sheet_columns(frame_count=4, frame_width=100, max_width=1000), 4)
        self.assertEqual(sheet_columns(frame_count=30, frame_width=100, max_width=1000), 10)

    def test_a_frame_wider_than_the_maximum_still_gets_one_column(self):
        self.assertEqual(sheet_columns(frame_count=3, frame_width=5000, max_width=4096), 1)

    def test_frames_are_laid_out_left_to_right_then_top_to_bottom(self):
        colors = [(255, 0, 0, 255), (0, 255, 0, 255), (0, 0, 255, 255)]
        frames = [Image.new('RGBA', (2, 3), color) for color in colors]

        sheet = build_sheet(frames, columns=2)

        self.assertEqual(sheet.size, (4, 6))
        self.assertEqual(sheet.getpixel((0, 0)), colors[0])
        self.assertEqual(sheet.getpixel((2, 0)), colors[1])
        self.assertEqual(sheet.getpixel((0, 3)), colors[2])
        self.assertEqual(sheet.getpixel((2, 3)), (0, 0, 0, 0))


if __name__ == '__main__':
    unittest.main()
