"""Run: python3 -m unittest discover tools"""

import unittest
import zlib

from extract_data import (
    DataError,
    convert_challenges,
    convert_item_database,
    convert_newsletters,
    convert_texts,
    load_xml,
    parse_xml,
)


def database(body: str) -> bytes:
    return f'<?xml version="1.0" encoding="utf-8"?><database>{body}</database>'.encode()


class ParseXmlTest(unittest.TestCase):
    def test_accepts_attributes_with_no_space_between_them(self):
        root = parse_xml(database('<group name="A"><item text="x"correct="true"/></group>'), 'quiz.bin')

        self.assertEqual(root[0][0].attrib, {'text': 'x', 'correct': 'true'})

    def test_accepts_double_hyphen_inside_comments(self):
        root = parse_xml(database('<!-- cash -- only --><group name="A"/>'), 'newsletter.xml')

        self.assertEqual(root[0].attrib['name'], 'A')

    def test_reads_windows_1252_bytes_in_a_file_that_claims_utf8(self):
        root = parse_xml(database('<group name="B\xe9chamel"/>').decode().encode('cp1252'), 'quiz.bin')

        self.assertEqual(root[0].attrib['name'], 'B\xe9chamel')

    def test_names_the_file_when_xml_is_broken(self):
        with self.assertRaises(DataError) as raised:
            parse_xml(b'<database><group></database>', 'broken.bin')

        self.assertIn('broken.bin', str(raised.exception))


class LoadXmlTest(unittest.TestCase):
    def test_inflates_zlib_data(self):
        root = load_xml(zlib.compress(database('<group name="A"/>')), 'a.bin', compressed=True)

        self.assertEqual(root[0].attrib['name'], 'A')

    def test_names_the_file_when_data_is_not_zlib(self):
        with self.assertRaises(DataError) as raised:
            load_xml(b'not zlib', 'a.bin', compressed=True)

        self.assertIn('a.bin', str(raised.exception))


class ConvertItemDatabaseTest(unittest.TestCase):
    def convert(self, body: str) -> list:
        return convert_item_database(parse_xml(database(body), 'test.bin'))

    def test_item_booleans_and_null_are_converted(self):
        item = self.convert('<group name="A"><item isNew="true" isLimited="false" texture="null"/></group>')[0]['items'][0]

        self.assertIs(item['isNew'], True)
        self.assertIs(item['isLimited'], False)
        self.assertIsNone(item['texture'])

    def test_item_numbers_stay_strings(self):
        item = self.convert('<group name="A"><item id="5000000" cost="2"/></group>')[0]['items'][0]

        self.assertEqual((item['id'], item['cost']), ('5000000', '2'))

    def test_item_cost_and_cash_default_to_zero(self):
        item = self.convert('<group name="A"><item name="x"/></group>')[0]['items'][0]

        self.assertEqual((item['cost'], item['cash']), ('0', '0'))

    def test_item_type_becomes_types_list(self):
        item = self.convert('<group name="A"><item type="chair , table"/></group>')[0]['items'][0]

        self.assertEqual(item['types'], ['chair', 'table'])
        self.assertNotIn('type', item)

    def test_item_children_are_kept(self):
        item = self.convert(
            '<group name="Quiz1"><item question="Q?"><choice text="Fruit" correct="true"/></item></group>'
        )[0]['items'][0]

        self.assertEqual(item['children'], [{'tag': 'choice', 'attributes': {'text': 'Fruit', 'correct': 'true'}}])

    def test_group_type_becomes_types_and_other_attributes_stay_raw(self):
        group = self.convert('<group name="Wall" type="wallItem" buttonName="null" flag="true"/>')[0]

        self.assertEqual(group['name'], 'Wall')
        self.assertEqual(group['types'], ['wallItem'])
        self.assertIsNone(group['buttonName'])
        self.assertEqual(group['flag'], 'true')  # ItemDatabase.as converts booleans on items only
        self.assertEqual(group['items'], [])


class ConvertChallengesTest(unittest.TestCase):
    def test_reads_tasks_and_rewards(self):
        root = parse_xml(
            b'<challenges><challenge name="Soup" id="0" text="Serve" iconName="FoodItem2" durationHours="24">'
            b'<serve recipe="Soup" containIngredients="" count="1000"/>'
            b'<reward><ingredients>Tomato, Basil</ingredients><recipes>Garden Salad</recipes></reward>'
            b'</challenge></challenges>',
            'challenge.bin',
        )

        challenge = convert_challenges(root)[0]

        self.assertEqual(challenge['id'], '0')
        self.assertEqual(challenge['durationHours'], '24')
        self.assertEqual(challenge['serve'], [{'recipe': 'Soup', 'containIngredients': '', 'count': '1000'}])
        self.assertEqual(challenge['rewardIngredients'], ['Tomato', 'Basil'])
        self.assertEqual(challenge['rewardRecipes'], ['Garden Salad'])


class ConvertTextsTest(unittest.TestCase):
    def test_trims_bodies_and_keeps_markup_from_cdata(self):
        root = parse_xml(
            b'<contents><content lang="en" name="ENGLISH">'
            b'<text id="Hello">\n\t\tHi there\n\t</text>'
            b'<text id="Level"><![CDATA[Level <FONT COLOR="#2F9AC8">%N%</FONT> !]]></text>'
            b'</content></contents>',
            'lang_en.bin',
        )

        content = convert_texts(root)[0]

        self.assertEqual(content['lang'], 'en')
        self.assertEqual(content['texts'], {'Hello': 'Hi there', 'Level': 'Level <FONT COLOR="#2F9AC8">%N%</FONT> !'})

    def test_first_text_wins_when_an_id_repeats(self):
        root = parse_xml(
            b'<contents><content lang="en"><text id="A">one</text><text id="A">two</text></content></contents>',
            'lang_en.bin',
        )

        self.assertEqual(convert_texts(root)[0]['texts'], {'A': 'one'})


class ConvertNewslettersTest(unittest.TestCase):
    def test_reads_id_date_and_text(self):
        root = parse_xml(
            b'<newsletters><!-- old -- one --><newsletter id="20" date="09/02/2010"><![CDATA[Hi]]></newsletter></newsletters>',
            'newsletter.xml',
        )

        self.assertEqual(convert_newsletters(root), [{'id': '20', 'date': '2010-02-09', 'text': 'Hi'}])


if __name__ == '__main__':
    unittest.main()
