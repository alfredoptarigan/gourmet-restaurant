"""Dump the Restaurant City data files in raw/ to JSON in data/.

Run: python3 tools/extract_data.py [raw_dir] [out_dir]

The client's *_bin resources are zlib-compressed XML. Conversion rules mirror the
AS3 loaders so ported game code sees the same values:
  ItemDatabase.as      front, avatar, restaurant, perk, ingredient, recipe, quiz, appointment
  ChallengeDatabase.as challenge
  TextGroup.as         lang_en, lang_fr
  NewsletterHandler.as newsletter
model.bin is the avatar Collada model; it is inflated to assets/avatar/avatar.dae. Its skin
bind poses, which Godot's Collada importer drops, are written to assets/avatar/skins.json.
"""

import json
import re
import sys
import xml.etree.ElementTree as ElementTree
import zlib
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

LIST_SEPARATOR = re.compile(r'\s*,\s*')
XML_COMMENT = re.compile(rb'<!--.*?-->', re.DOTALL)
ATTRIBUTES_WITHOUT_SPACE = re.compile(rb'"(?=[A-Za-z_][\w:.-]*=")')
ITEM_OPEN_TAG = re.compile(rb'<item[\s/>]')


class DataError(Exception):
    """A source file is missing, corrupt, or not shaped the way its loader expects."""


def parse_xml(data: bytes, source_name: str) -> ElementTree.Element:
    # Flash's E4X parser tolerates two things expat rejects, and the real files rely on both:
    # "--" inside comments (newsletter.xml) and attributes with no space between them (quiz.bin).
    # ponytail: comments are stripped by regex, so a "<!--" inside CDATA would be eaten too;
    # no file has one. Switch to a tokenizer if that ever changes.
    without_comments = to_utf8(XML_COMMENT.sub(b'', data))
    try:
        return ElementTree.fromstring(without_comments)
    except ElementTree.ParseError:
        repaired = ATTRIBUTES_WITHOUT_SPACE.sub(b'" ', without_comments)
    try:
        return ElementTree.fromstring(repaired)
    except ElementTree.ParseError as error:
        raise DataError(f'{source_name}: not valid XML ({error})') from error


def to_utf8(data: bytes) -> bytes:
    # quiz.bin declares UTF-8 but was saved as Windows-1252 ("Béchamel", "Crêpe").
    try:
        data.decode('utf-8')
        return data
    except UnicodeDecodeError:
        return data.decode('cp1252', errors='replace').encode('utf-8')


def load_xml(data: bytes, source_name: str, compressed: bool) -> ElementTree.Element:
    return parse_xml(inflate(data, source_name) if compressed else data, source_name)


def inflate(data: bytes, source_name: str) -> bytes:
    try:
        return zlib.decompress(data)
    except zlib.error as error:
        raise DataError(f'{source_name}: not zlib data ({error})') from error


def split_list(value: str) -> list:
    return [part for part in LIST_SEPARATOR.split(value.strip()) if part]


def null_to_none(value: str):
    return None if value == 'null' else value


def convert_item_value(value: str):
    if value == 'true':
        return True
    if value == 'false':
        return False
    return null_to_none(value)


def element_text(element: ElementTree.Element) -> str:
    return ''.join(element.itertext()).strip()


def convert_child(element: ElementTree.Element) -> dict:
    # The AS3 client keeps item children as raw XML, so values stay unconverted strings here.
    child = {'tag': element.tag, 'attributes': dict(element.attrib)}
    text = (element.text or '').strip()
    if text:
        child['text'] = text
    if len(element):
        child['children'] = [convert_child(grandchild) for grandchild in element]
    return child


def convert_item(element: ElementTree.Element) -> dict:
    # Numbers stay strings, as in the client; "0" keeps the defaults the same type as real values.
    item = {'cash': '0', 'cost': '0'}
    for name, value in element.attrib.items():
        if name == 'type':
            item['types'] = split_list(value)
        else:
            item[name] = convert_item_value(value)
    if len(element):
        item['children'] = [convert_child(child) for child in element]
    return item


def convert_group(element: ElementTree.Element) -> dict:
    group = {'name': element.attrib.get('name', '')}
    for name, value in element.attrib.items():
        if name == 'type':
            if value:
                group['types'] = split_list(value)
        elif name != 'name':
            group[name] = null_to_none(value)
    group['items'] = [convert_item(item) for item in element.findall('item')]
    return group


def convert_item_database(root: ElementTree.Element) -> list:
    return [convert_group(group) for group in root.findall('group')]


def convert_challenge(element: ElementTree.Element) -> dict:
    challenge = dict(element.attrib)
    challenge['serve'] = [dict(serve.attrib) for serve in element.findall('serve')]
    challenge['rewardIngredients'] = [
        name for node in element.findall('reward/ingredients') for name in split_list(element_text(node))
    ]
    # The data says <recipes>; ChallengeDatabase.as reads <recipe>, so the original client
    # never granted these. Dumped as the data intends.
    challenge['rewardRecipes'] = [
        name for node in element.findall('reward/recipes') for name in split_list(element_text(node))
    ]
    return challenge


def convert_challenges(root: ElementTree.Element) -> list:
    return [convert_challenge(challenge) for challenge in root.findall('challenge')]


def convert_texts(root: ElementTree.Element) -> list:
    contents = []
    for content in root.findall('content'):
        texts = {}
        for text in content.findall('text'):
            texts.setdefault(text.attrib.get('id', ''), element_text(text))
        contents.append({**content.attrib, 'texts': texts})
    return contents


def convert_newsletter_date(value: str, newsletter_id: str) -> str:
    parts = value.split('/')
    if len(parts) != 3 or not all(part.isdigit() for part in parts):
        raise DataError(f'newsletter {newsletter_id}: date {value!r} is not DD/MM/YYYY')
    day, month, year = parts
    return f'{int(year):04d}-{int(month):02d}-{int(day):02d}'


def convert_newsletters(root: ElementTree.Element) -> list:
    newsletters = []
    for newsletter in root.findall('newsletter'):
        newsletter_id = newsletter.attrib.get('id', '')
        date = convert_newsletter_date(newsletter.attrib.get('date', ''), newsletter_id)
        newsletters.append({'id': newsletter_id, 'date': date, 'text': element_text(newsletter)})
    return newsletters


def convert_bind(matrix: list, unit: float) -> dict:
    """A Collada 4x4 (row-major, Z-up) as a Godot transform: basis columns x, y, z and origin.

    Godot's Collada importer turns a Z-up point (x, y, z) into Y-up (x, z, -y) and scales
    lengths by the file's unit, so the bind poses must make the same trip to match the
    meshes and bones it imported.
    """
    def to_y_up(vector: list) -> list:
        return [vector[0], vector[2], -vector[1]]

    def tidy(vector: list) -> list:
        return [round(value, BIND_PRECISION) + 0.0 for value in vector]

    rows = [matrix[0:4], matrix[4:8], matrix[8:12]]
    columns = [[rows[row][column] for row in range(3)] for column in range(3)]
    return {
        'x': tidy(to_y_up(columns[0])),
        'y': tidy(to_y_up(columns[2])),
        'z': tidy([-value for value in to_y_up(columns[1])]),
        'origin': tidy([unit * value for value in to_y_up([row[3] for row in rows])]),
    }


def source_id(skin: ElementTree.Element, semantic: str, controller_id: str) -> str:
    for joint_input in skin.findall('{*}joints/{*}input'):
        if joint_input.get('semantic') == semantic:
            return joint_input.get('source', '').lstrip('#')
    raise DataError(f'{MODEL_SOURCE}: controller {controller_id} has no {semantic} input')


def extract_skins(root: ElementTree.Element) -> dict:
    """Mesh node name -> its bones with their inverse bind poses, in Godot space.

    The bind shape matrix is left out on purpose: Godot's importer bakes it into the vertices.
    """
    up_axis = root.findtext('{*}asset/{*}up_axis', 'Y_UP').strip()
    if up_axis != 'Z_UP':
        raise DataError(f'{MODEL_SOURCE}: up axis is {up_axis}; only Z_UP is handled')
    unit_element = root.find('{*}asset/{*}unit')
    unit = float(unit_element.get('meter', DEFAULT_UNIT)) if unit_element is not None else DEFAULT_UNIT
    bone_names = {
        node.get('sid'): node.get('name')
        for node in root.findall('.//{*}node')
        if node.get('type') == 'JOINT' and node.get('sid')
    }
    mesh_names = {}
    for node in root.findall('.//{*}node'):
        instance = node.find('{*}instance_controller')
        if instance is not None:
            mesh_names[instance.get('url', '').lstrip('#')] = node.get('name')
    skins = {}
    for controller in root.findall('.//{*}controller'):
        controller_id = controller.get('id', '')
        skin = controller.find('{*}skin')
        if skin is None or controller_id not in mesh_names:
            continue
        sources = {source.get('id'): source for source in skin.findall('{*}source')}
        joints = sources[source_id(skin, 'JOINT', controller_id)].findtext('{*}Name_array', '').split()
        values = [
            float(value)
            for value in sources[source_id(skin, 'INV_BIND_MATRIX', controller_id)].findtext('{*}float_array', '').split()
        ]
        if len(values) != MATRIX_SIZE * len(joints):
            raise DataError(f'{MODEL_SOURCE}: controller {controller_id} has {len(joints)} joints but {len(values)} bind values')
        binds = []
        for index, joint in enumerate(joints):
            if joint not in bone_names:
                raise DataError(f'{MODEL_SOURCE}: controller {controller_id} names unknown joint {joint}')
            matrix = values[index * MATRIX_SIZE:(index + 1) * MATRIX_SIZE]
            binds.append({'bone': bone_names[joint], **convert_bind(matrix, unit)})
        skins[mesh_names[controller_id]] = binds
    return skins


# (source file, output name, converter, zlib-compressed)
SOURCES = [
    ('front.bin', 'front', convert_item_database, True),
    ('avatar.bin', 'avatar', convert_item_database, True),
    ('restaurant.bin', 'restaurant', convert_item_database, True),
    ('perk.bin', 'perk', convert_item_database, True),
    ('ingredient.bin', 'ingredient', convert_item_database, True),
    ('recipe.bin', 'recipe', convert_item_database, True),
    ('quiz.bin', 'quiz', convert_item_database, True),
    ('appointment.bin', 'appointment', convert_item_database, True),
    ('challenge.bin', 'challenge', convert_challenges, True),
    ('lang_en.bin', 'lang_en', convert_texts, True),
    ('lang_fr.bin', 'lang_fr', convert_texts, True),
    ('newsletter.xml', 'newsletter', convert_newsletters, False),
]
MODEL_SOURCE = 'model.bin'
MODEL_OUTPUT = PROJECT_ROOT / 'assets' / 'avatar' / 'avatar.dae'
SKINS_OUTPUT = MODEL_OUTPUT.with_name('skins.json')
MATRIX_SIZE = 16
DEFAULT_UNIT = 1.0
BIND_PRECISION = 6


def read_source(raw_dir: Path, source_name: str) -> bytes:
    try:
        return (raw_dir / source_name).read_bytes()
    except OSError as error:
        raise DataError(f'{source_name}: cannot read from {raw_dir} ({error})') from error


def describe(converter, converted: list) -> str:
    if converter is convert_item_database:
        return f'{len(converted)} groups, {sum(len(group["items"]) for group in converted)} items'
    if converter is convert_texts:
        return f'{sum(len(content["texts"]) for content in converted)} texts'
    return f'{len(converted)} entries'


def check_item_count(data: bytes, converted: list, source_name: str) -> None:
    expected = len(ITEM_OPEN_TAG.findall(XML_COMMENT.sub(b'', data)))
    actual = sum(len(group['items']) for group in converted)
    if expected != actual:
        raise DataError(f'{source_name}: source has {expected} <item> tags but {actual} were converted')


def extract_source(raw_dir: Path, out_dir: Path, source_name: str, output_name: str, converter, compressed: bool) -> str:
    data = read_source(raw_dir, source_name)
    xml_bytes = inflate(data, source_name) if compressed else data
    converted = converter(parse_xml(xml_bytes, source_name))
    if converter is convert_item_database:
        check_item_count(xml_bytes, converted, source_name)
    output_path = out_dir / f'{output_name}.json'
    output_path.write_text(json.dumps(converted, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    return f'{source_name:16} -> {output_path.name:18} {describe(converter, converted)}'


def extract_model(raw_dir: Path) -> str:
    collada = inflate(read_source(raw_dir, MODEL_SOURCE), MODEL_SOURCE)
    root = parse_xml(collada, MODEL_SOURCE)
    if not root.tag.endswith('COLLADA'):
        raise DataError(f'{MODEL_SOURCE}: root element is {root.tag}, expected COLLADA')
    MODEL_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    skins = extract_skins(root)
    MODEL_OUTPUT.write_bytes(collada)
    SKINS_OUTPUT.write_text(json.dumps(skins, indent=1) + '\n', encoding='utf-8')
    return (f'{MODEL_SOURCE:16} -> {MODEL_OUTPUT.name:18} {len(collada)} bytes\n'
            f'{MODEL_SOURCE:16} -> {SKINS_OUTPUT.name:18} {len(skins)} skinned meshes')


def main(arguments: list) -> int:
    raw_dir = Path(arguments[0]) if arguments else PROJECT_ROOT / 'raw'
    out_dir = Path(arguments[1]) if len(arguments) > 1 else PROJECT_ROOT / 'data'
    try:
        out_dir.mkdir(parents=True, exist_ok=True)
        for source in SOURCES:
            print(extract_source(raw_dir, out_dir, *source))
        print(extract_model(raw_dir))
    except (DataError, OSError) as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
