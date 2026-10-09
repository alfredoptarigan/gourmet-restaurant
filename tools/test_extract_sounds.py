"""Run: python3 -m unittest discover tools"""

import unittest

from extract_sounds import sound_name


class SoundNameTest(unittest.TestCase):
    def test_takes_the_class_name_out_of_a_jpexs_file_name(self):
        self.assertEqual(sound_name('9_SfxCash_SfxCash.mp3'), 'SfxCash')
        self.assertEqual(sound_name('1_MusicClassical_MusicClassical.mp3'), 'MusicClassical')

    def test_keeps_underscores_that_belong_to_the_name(self):
        self.assertEqual(sound_name('12_Sfx_Door_Open_Sfx_Door_Open.mp3'), 'Sfx_Door_Open')

    def test_ignores_files_that_are_not_named_sounds(self):
        self.assertIsNone(sound_name('3.mp3'))
        self.assertIsNone(sound_name('notes.txt'))
        self.assertIsNone(sound_name('4_OneName_OtherName.mp3'))


if __name__ == '__main__':
    unittest.main()
