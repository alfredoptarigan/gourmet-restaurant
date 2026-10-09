"""Render the named symbols of an asset SWF to sprite sheets for Godot.

Run: python3 tools/extract_sprites.py [group ...]      (default: indoor avatar)

For raw/<group>_asset.swf this writes
  assets/sprites/<group>/<ClassName>.png   every timeline frame of the symbol, in a grid
  assets/sprites/<group>.json              frame count, grid columns, frame size, origin, bounds

The art is vector, so JPEXS rasterises it at ZOOM times the original size (each sprite's
`zoom` says what it got: long animations fall back to 1). `origin` is where
the symbol's registration point sits inside one frame, in sheet pixels; the game positions
that point on the tile, exactly as Flash positioned the MovieClip.

Needs Pillow, Java and JPEXS Free Flash Decompiler. Override the paths with:
  JAVA       java binary   (default /opt/homebrew/opt/openjdk/bin/java)
  FFDEC_JAR  ffdec.jar     (default ~/.local/opt/jpexs/ffdec.jar)
"""

import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_GROUPS = ['indoor', 'avatar']
DEFAULT_JAVA = '/opt/homebrew/opt/openjdk/bin/java'
DEFAULT_FFDEC_JAR = '~/.local/opt/jpexs/ffdec.jar'

ZOOM = 2
# Sheets are single textures, so they must stay inside what a GPU will load.
MAX_SHEET_SIZE = 8192

SWF_HEADER_BYTES = 8
TAG_END = 0
TAG_DEFINE_SPRITE = 39
TAG_SYMBOL_CLASS = 76
LONG_TAG_LENGTH = 63

ROOT_GROUP_TRANSLATION = re.compile(
    r'<g transform="matrix\(\s*[-\d.eE]+,\s*[-\d.eE]+,\s*[-\d.eE]+,\s*[-\d.eE]+,\s*([-\d.eE]+),\s*([-\d.eE]+)\s*\)"'
)
EXPORT_DIR_NAME = re.compile(r'DefineSprite_(\d+)(?:_|$)')


class SpriteError(Exception):
    """A SWF or a JPEXS export is missing, corrupt, or not shaped as expected."""


def swf_body(data: bytes) -> bytes:
    signature = data[:3]
    if signature == b'FWS':
        return data[SWF_HEADER_BYTES:]
    if signature == b'CWS':
        try:
            return zlib.decompress(data[SWF_HEADER_BYTES:])
        except zlib.error as error:
            raise SpriteError(f'compressed SWF body is corrupt ({error})') from error
    raise SpriteError(f'not a SWF file (signature {signature!r})')


def iter_tags(body: bytes):
    # Skip the stage RECT (5-bit field size, then four fields), frame rate and frame count.
    rect_bits = 5 + 4 * (body[0] >> 3)
    position = (rect_bits + 7) // 8 + 4
    while position + 2 <= len(body):
        code_and_length, = struct.unpack_from('<H', body, position)
        position += 2
        code, length = code_and_length >> 6, code_and_length & LONG_TAG_LENGTH
        if length == LONG_TAG_LENGTH:
            length, = struct.unpack_from('<I', body, position)
            position += 4
        yield code, body[position:position + length]
        position += length
        if code == TAG_END:
            return


def exported_sprite_names(data: bytes) -> dict:
    """Character id -> class name, for sprites that game code can instantiate by name."""
    sprite_ids = set()
    names = {}
    for code, tag in iter_tags(swf_body(data)):
        if code == TAG_DEFINE_SPRITE:
            sprite_ids.add(struct.unpack_from('<H', tag)[0])
        elif code == TAG_SYMBOL_CLASS:
            count, = struct.unpack_from('<H', tag)
            position = 2
            for _ in range(count):
                character_id, = struct.unpack_from('<H', tag, position)
                end = tag.index(b'\0', position + 2)
                names[character_id] = tag[position + 2:end].decode('utf-8')
                position = end + 1
    # "<swf>_fla.Name_123" classes are timeline internals; game code never asks for them.
    return {
        character_id: name
        for character_id, name in names.items()
        if character_id in sprite_ids and '.' not in name
    }


def parse_origin(svg: str, sprite_name: str) -> tuple:
    """Where the registration point sits in the frame, in unzoomed pixels."""
    match = ROOT_GROUP_TRANSLATION.search(svg)
    if not match:
        raise SpriteError(f'{sprite_name}: SVG export has no root transform to read the origin from')
    return float(match.group(1)), float(match.group(2))


def frame_bounds(frame: Image.Image, origin: tuple) -> list:
    """Left, top, right, bottom of the drawn pixels, relative to the registration point."""
    box = frame.getbbox()
    if box is None:
        return [0.0, 0.0, 0.0, 0.0]
    origin_x, origin_y = origin
    return [round(box[0] - origin_x, 2), round(box[1] - origin_y, 2), round(box[2] - origin_x, 2), round(box[3] - origin_y, 2)]


def sheet_columns(frame_count: int, frame_width: int, max_width: int) -> int:
    return max(1, min(frame_count, max_width // max(1, frame_width)))


def sheet_fits(frame_count: int, frame_width: int, frame_height: int, max_size: int) -> bool:
    columns = sheet_columns(frame_count, frame_width, max_size)
    rows = (frame_count + columns - 1) // columns
    return frame_width * columns <= max_size and frame_height * rows <= max_size


def build_sheet(frames: list, columns: int) -> Image.Image:
    frame_width, frame_height = frames[0].size
    rows = (len(frames) + columns - 1) // columns
    sheet = Image.new('RGBA', (frame_width * columns, frame_height * rows), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        sheet.paste(frame, ((index % columns) * frame_width, (index // columns) * frame_height))
    return sheet


def run_jpexs(java: str, ffdec: Path, swf_path: Path, out_dir: Path, image_format: str, ids: list, zoom: int) -> None:
    command = [
        java, '-Djava.awt.headless=true', '-jar', str(ffdec), '-zoom', str(zoom),
        '-selectid', ','.join(map(str, ids)),
        '-format', f'sprite:{image_format}', '-export', 'sprite', str(out_dir), str(swf_path),
    ]
    try:
        subprocess.run(command, check=True, capture_output=True, text=True)
    except FileNotFoundError as error:
        raise SpriteError(f'Java not found at {java}. Set the JAVA environment variable.') from error
    except subprocess.CalledProcessError as error:
        raise SpriteError(f'JPEXS failed on {swf_path.name}: {error.stderr.strip()[-500:]}') from error


def export_dirs(out_dir: Path) -> dict:
    """Character id -> the folder JPEXS wrote that sprite's frames into."""
    found = {}
    for path in out_dir.iterdir():
        match = EXPORT_DIR_NAME.match(path.name)
        if match and path.is_dir():
            found[int(match.group(1))] = path
    return found


def frame_files(sprite_dir: Path, extension: str) -> list:
    return sorted(sprite_dir.glob(f'*.{extension}'), key=lambda path: int(path.stem))


def halve(frame: Image.Image) -> Image.Image:
    return frame.resize(((frame.width + 1) // 2, (frame.height + 1) // 2), Image.LANCZOS)


def write_sprite(name: str, png_dir: Path, svg_dir: Path, sheets_dir: Path):
    """Writes the sheet and returns its metadata, or None if it cannot fit in one texture."""
    png_files = frame_files(png_dir, 'png')
    svg_files = frame_files(svg_dir, 'svg')
    if not png_files or not svg_files:
        raise SpriteError(f'{name}: JPEXS exported no frames')
    frames = [Image.open(path).convert('RGBA') for path in png_files]
    if any(frame.size != frames[0].size for frame in frames):
        raise SpriteError(f'{name}: frames differ in size, so one origin cannot describe them all')
    zoom = ZOOM
    # Long full-screen animations do not fit at full zoom: fall back to the original size.
    while zoom > 1 and not sheet_fits(len(frames), *frames[0].size, MAX_SHEET_SIZE):
        frames = [halve(frame) for frame in frames]
        zoom //= 2
    frame_width, frame_height = frames[0].size
    if not sheet_fits(len(frames), frame_width, frame_height, MAX_SHEET_SIZE):
        return None
    origin_x, origin_y = parse_origin(svg_files[0].read_text(encoding='utf-8'), name)
    columns = sheet_columns(len(frames), frame_width, MAX_SHEET_SIZE)
    build_sheet(frames, columns).save(sheets_dir / f'{name}.png')
    origin = (round(origin_x * zoom, 2), round(origin_y * zoom, 2))
    return {
        'frames': len(frames),
        'columns': columns,
        'width': frame_width,
        'height': frame_height,
        'zoom': zoom,
        'origin': list(origin),
        # Flash sized an item's tile footprint from its first frame, so that frame is measured.
        'bounds': frame_bounds(frames[0], origin),
    }


def extract_group(group: str, java: str, ffdec: Path) -> str:
    swf_path = PROJECT_ROOT / 'raw' / f'{group}_asset.swf'
    try:
        names = exported_sprite_names(swf_path.read_bytes())
    except OSError as error:
        raise SpriteError(f'cannot read {swf_path} ({error})') from error
    if not names:
        raise SpriteError(f'{swf_path.name}: no named sprites found')
    sheets_dir = PROJECT_ROOT / 'assets' / 'sprites' / group
    sheets_dir.mkdir(parents=True, exist_ok=True)
    ids = sorted(names)
    sprites = {}
    skipped = []
    too_large = []
    with tempfile.TemporaryDirectory() as png_root, tempfile.TemporaryDirectory() as svg_root:
        run_jpexs(java, ffdec, swf_path, Path(png_root), 'png', ids, ZOOM)
        # The SVG is read only for the registration point, so it is exported unzoomed.
        run_jpexs(java, ffdec, swf_path, Path(svg_root), 'svg', ids, 1)
        png_dirs, svg_dirs = export_dirs(Path(png_root)), export_dirs(Path(svg_root))
        for character_id in ids:
            name = names[character_id]
            if character_id not in png_dirs or character_id not in svg_dirs:
                skipped.append(name)  # an empty symbol: JPEXS has nothing to draw
                continue
            sprite = write_sprite(name, png_dirs[character_id], svg_dirs[character_id], sheets_dir)
            if sprite is None:
                too_large.append(name)
                (sheets_dir / f'{name}.png').unlink(missing_ok=True)
            else:
                sprites[name] = sprite
    metadata = {'zoom': ZOOM, 'sprites': dict(sorted(sprites.items()))}
    metadata_path = sheets_dir.parent / f'{group}.json'
    metadata_path.write_text(json.dumps(metadata, indent=1) + '\n', encoding='utf-8')
    summary = f'{swf_path.name}: {len(sprites)} sprites -> {sheets_dir.relative_to(PROJECT_ROOT)}'
    if skipped:
        summary += f'\n  no frames, skipped: {", ".join(skipped)}'
    if too_large:
        summary += f'\n  too large for one texture, skipped: {", ".join(too_large)}'
    return summary


def main(arguments: list) -> int:
    java = os.environ.get('JAVA', DEFAULT_JAVA)
    ffdec = Path(os.environ.get('FFDEC_JAR', DEFAULT_FFDEC_JAR)).expanduser()
    if not ffdec.exists():
        print(f'error: JPEXS not found at {ffdec}. Set the FFDEC_JAR environment variable.', file=sys.stderr)
        return 1
    try:
        for group in arguments or DEFAULT_GROUPS:
            print(extract_group(group, java, ffdec))
    except (SpriteError, OSError) as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
