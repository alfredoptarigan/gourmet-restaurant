"""Export the sounds of raw/sound_asset.swf to assets/sounds/<ClassName>.mp3.

Run: python3 tools/extract_sounds.py

The game asks for sounds by class name (GameSound.as), so that is what the files are called.
Needs Java and JPEXS; see extract_sprites.py for the JAVA and FFDEC_JAR variables.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SOURCE = PROJECT_ROOT / 'raw' / 'sound_asset.swf'
OUTPUT_DIR = PROJECT_ROOT / 'assets' / 'sounds'
DEFAULT_JAVA = '/opt/homebrew/opt/openjdk/bin/java'
DEFAULT_FFDEC_JAR = '~/.local/opt/jpexs/ffdec.jar'

# JPEXS names a sound "<character id>_<export name>_<class name>.mp3".
EXPORTED_SOUND = re.compile(r'^\d+_(.+)\.mp3$')


def sound_name(file_name: str):
    """The sound's class name, or None if the file is not a named sound."""
    match = EXPORTED_SOUND.match(file_name)
    if not match:
        return None
    # The export name and the class name are the same text twice, joined by "_".
    doubled = match.group(1)
    half = (len(doubled) - 1) // 2
    if len(doubled) % 2 == 0 or doubled[half] != '_' or doubled[:half] != doubled[half + 1:]:
        return None
    return doubled[:half]


def main() -> int:
    java = os.environ.get('JAVA', DEFAULT_JAVA)
    ffdec = Path(os.environ.get('FFDEC_JAR', DEFAULT_FFDEC_JAR)).expanduser()
    if not SOURCE.exists():
        print(f'error: {SOURCE} is missing', file=sys.stderr)
        return 1
    if not ffdec.exists():
        print(f'error: JPEXS not found at {ffdec}. Set the FFDEC_JAR environment variable.', file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory() as exported:
        command = [
            java, '-Djava.awt.headless=true', '-jar', str(ffdec),
            '-format', 'sound:mp3_wav', '-export', 'sound', exported, str(SOURCE),
        ]
        try:
            subprocess.run(command, check=True, capture_output=True, text=True)
        except FileNotFoundError:
            print(f'error: Java not found at {java}. Set the JAVA environment variable.', file=sys.stderr)
            return 1
        except subprocess.CalledProcessError as error:
            print(f'error: JPEXS failed on {SOURCE.name}: {error.stderr.strip()[-500:]}', file=sys.stderr)
            return 1
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        names = []
        for path in sorted(Path(exported).iterdir()):
            name = sound_name(path.name)
            if name is not None:
                shutil.copyfile(path, OUTPUT_DIR / f'{name}.mp3')
                names.append(name)
    if not names:
        print(f'error: {SOURCE.name} held no sounds JPEXS could export as MP3', file=sys.stderr)
        return 1
    print(f'{SOURCE.name}: {len(names)} sounds -> {OUTPUT_DIR.relative_to(PROJECT_ROOT)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
