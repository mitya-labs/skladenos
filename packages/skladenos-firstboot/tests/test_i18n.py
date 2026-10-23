"""Каталог переводов: у каждого ключа есть оба языка и совпадают подстановки %."""
import os, re, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "files", "usr", "lib", "skladenos-firstboot"))
from skladenos_firstboot import i18n  # noqa: E402


class Catalog(unittest.TestCase):
    def tearDown(self):
        i18n.set_lang("en")

    def test_default_is_english(self):
        self.assertEqual(i18n.DEFAULT, "en")
        self.assertEqual(i18n.t("next"), "Next")

    def test_all_keys_in_all_languages_with_same_placeholders(self):
        ph = lambda s: sorted(re.findall(r"%[sd]", s))
        for key, tr in i18n.STRINGS.items():
            if key in ("lang.title", "lang.button"):  # двуязычные подписи, одинаковые везде (en как запасной)
                continue
            self.assertEqual(set(tr), set(i18n.LANGS), key)
            self.assertEqual(ph(tr["en"]), ph(tr["ru"]), key)
            self.assertTrue(all(tr.values()), key)

    def test_languages(self):
        self.assertEqual(sorted(i18n.LANGS), ["cs", "de", "en", "es", "fr", "it", "nl", "pl", "pt", "ru", "tr", "uk"])
        i18n.set_lang("de")
        self.assertEqual(i18n.t("next"), "Weiter")
        i18n.set_lang("uk")
        self.assertEqual(i18n.t("next"), "Далі")

    def test_switch_and_fallback(self):
        i18n.set_lang("ru")
        self.assertEqual(i18n.t("next"), "Далее")
        self.assertEqual(i18n.t("acc.short_pw", 6), "Пароль слишком короткий (минимум 6 символов)")
        i18n.set_lang("xx")  # неизвестный язык -> по умолчанию
        self.assertEqual(i18n.get_lang(), "en")
        self.assertEqual(i18n.t("no.such.key"), "no.such.key")

    def test_backend_messages_follow_language(self):
        from skladenos_firstboot import account
        i18n.set_lang("ru")
        self.assertIn("Пароли", account.validate_password("abcdef1", "x"))
        i18n.set_lang("en")
        self.assertIn("do not match", account.validate_password("abcdef1", "x"))


if __name__ == "__main__":
    unittest.main()
