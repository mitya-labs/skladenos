"""Тесты бэкендов на заглушках, без root и без железа:  python3 -m unittest discover -s packages/skladenos-firstboot/tests"""
import json, os, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "files", "usr", "lib", "skladenos-firstboot"))
from skladenos_firstboot import account, bluetooth as bt, wifi  # noqa: E402


def fake(name, mode=None):
    path = os.path.join(HERE, name)
    if mode:
        os.environ["FAKE_BT_MODE"] = mode
    os.chmod(path, 0o755)
    return path


class ParseBt(unittest.TestCase):
    def test_lines(self):
        p = bt.parse_line
        self.assertEqual(p("\x1b[0;92m[NEW]\x1b[0m Device AA:BB:CC:00:00:02 Some Keyboard"), bt.Event("new", "AA:BB:CC:00:00:02", "Some Keyboard"))
        self.assertEqual(p("[bluetooth]# [CHG] Device aa:bb:cc:00:00:02 Paired: yes").text, "Paired=yes")
        self.assertEqual(p("[agent] Confirm passkey 123456 (yes/no): ").kind, "confirm")
        self.assertEqual(p("[agent] Passkey: 000123").text, "000123")
        self.assertEqual(p("[agent] PIN code: 1234").kind, "passkey")
        self.assertEqual(p("[agent] Enter PIN code: ").kind, "pin_request")
        self.assertEqual(p("Failed to pair: org.bluez.Error.AuthenticationFailed").kind, "pair_failed")
        self.assertIsNone(p("Discovery started"))

    def test_splitter_prompt_without_newline(self):
        s = bt.LineSplitter()
        self.assertEqual(s.feed("abc\n[agent] Confirm passkey 1 (yes"), ["abc"])
        self.assertEqual([bt.parse_line(l).kind for l in s.feed("/no): ")], ["confirm"])

    def test_keyboard_detect(self):
        self.assertTrue(bt.BtDevice("A", "X", icon="input-keyboard").is_keyboard)
        self.assertTrue(bt.BtDevice("A", "Logitech K380 Keyboard").is_keyboard)
        self.assertFalse(bt.BtDevice("A", "Наушники", icon="audio-headset").is_keyboard)
        self.assertFalse(bt.BtDevice("AA:BB:CC:00:00:03", "AA-BB-CC-00-00-03").has_real_name)


class BtSession(unittest.TestCase):
    def run_pair(self, mode):
        b = bt.BluetoothctlBackend(binary=fake("fake_bluetoothctl.py", mode))
        self.addCleanup(b.stop)
        ok, why = b.available()
        return b, ok, why

    def test_scan_and_pair_passkey(self):
        b, ok, _ = self.run_pair("passkey")
        self.assertTrue(ok)
        b.start_scan()
        import time
        for _ in range(30):
            devs = b.devices()
            if devs and devs[0].icon:
                break
            time.sleep(0.2)
        self.assertEqual([d.name for d in devs][0], "Logitech K380 Keyboard")  # клавиатура первой
        self.assertNotIn("AA-BB-CC-00-00-03", [d.name for d in devs])
        events = []
        ok, msg = b.pair("AA:BB:CC:00:00:02", lambda k, t: events.append((k, t)), timeout=10)
        self.assertTrue(ok, msg)
        self.assertIn(("passkey", "123456"), events)

    def test_pair_confirm(self):
        b, _, _ = self.run_pair("confirm")
        events = []
        ok, msg = b.pair("AA:BB:CC:00:00:02", lambda k, t: events.append((k, t)), timeout=10)
        self.assertTrue(ok, msg)
        self.assertIn(("passkey_confirm", "654321"), events)

    def test_pair_fail(self):
        b, _, _ = self.run_pair("fail")
        ok, msg = b.pair("AA:BB:CC:00:00:02", lambda k, t: None, timeout=10)
        self.assertFalse(ok)
        self.assertIn("AuthenticationFailed", msg)

    def test_no_controller(self):
        _, ok, why = self.run_pair("noctl")
        self.assertFalse(ok)
        self.assertIn("adapter", why)

    def test_missing_binary(self):
        ok, why = bt.BluetoothctlBackend(binary="/nonexistent/bluetoothctl").available()
        self.assertFalse(ok)


class Wifi(unittest.TestCase):
    def setUp(self):
        self.w = wifi.NmcliBackend(binary=fake("fake_nmcli.py"))

    def test_terse(self):
        self.assertEqual(wifi.split_terse(r"a\:b:c\\d:"), ["a:b", "c\\d", ""])

    def test_scan_dedupe_hidden(self):
        nets = self.w.scan()
        self.assertEqual([n.ssid for n in nets], ["Кафе", "Home-5G", "Weird:Name"])
        self.assertTrue(nets[0].in_use and not nets[0].secured)
        self.assertEqual(nets[1].signal, 82)

    def test_connect(self):
        ok, msg = self.w.connect("Home-5G", "bad")
        self.assertFalse(ok)
        self.assertIn("password", msg.lower())
        ok, msg = self.w.connect("Home-5G", "goodpass")
        self.assertTrue(ok)
        self.assertIn("internet is available", msg)
        self.assertTrue(self.w.connect("Кафе")[0])

    def test_current(self):
        self.assertEqual(self.w.current(), "Кафе")
        self.assertTrue(self.w.available()[0])


class Account(unittest.TestCase):
    def test_validate(self):
        v = account.validate_username
        self.assertIsNone(v("skladen"))
        self.assertIsNone(v("a-b_1"))
        for bad in ("", "Root", "1abc", "a b", "root", "x" * 40, "имя"):
            self.assertIsNotNone(v(bad), bad)
        self.assertIsNotNone(v("bob", taken=["bob"], current="skladen"))
        self.assertIsNone(v("skladen", taken=["skladen"], current="skladen"))
        p = account.validate_password
        self.assertIsNone(p("secret1", "secret1"))
        self.assertIsNotNone(p("1234"))
        self.assertIsNotNone(p("abc"))
        self.assertIsNotNone(p("secret1", "secret2"))
        self.assertIsNotNone(p("pass\nword1"))

    def rec(self, rc=0):
        calls = []
        def run(args, inp=None):
            calls.append((args, inp))
            return rc, ""
        return run, calls

    def test_apply_rename_and_flag(self):
        with tempfile.TemporaryDirectory() as d:
            run, calls = self.rec()
            r = account.apply_changes("skladen", "dima", "s3cret!", run, d, taken=["skladen", "root"])
            self.assertEqual(r, {"ok": True, "rename_pending": True})
            self.assertEqual(calls, [(["chpasswd"], "skladen:s3cret!\n")])  # пароль не в argv
            self.assertTrue(account.is_done(d))
            self.assertEqual(open(os.path.join(d, "rename-pending")).read(), "skladen dima\n")
            # после флага helper отказывает
            self.assertFalse(account.apply_changes("skladen", "x1", "s3cret!", run, d, taken=[])["ok"])

    def test_apply_same_name_and_errors(self):
        with tempfile.TemporaryDirectory() as d:
            run, _ = self.rec()
            r = account.apply_changes("skladen", "skladen", "s3cret!", run, d, taken=["skladen"])
            self.assertEqual(r, {"ok": True, "rename_pending": False})
            self.assertFalse(os.path.exists(os.path.join(d, "rename-pending")))
        with tempfile.TemporaryDirectory() as d:
            self.assertFalse(account.apply_changes("skladen", "dima", "1234", self.rec()[0], d, taken=[])["ok"])
            self.assertFalse(account.is_done(d))
            r = account.apply_changes("skladen", "dima", "s3cret!", self.rec(1)[0], d, taken=[])
            self.assertFalse(r["ok"])
            self.assertFalse(account.is_done(d))  # флаг только после успеха

    def test_pending_rename(self):
        with tempfile.TemporaryDirectory() as d:
            open(os.path.join(d, "rename-pending"), "w").write("skladen dima\n")
            df = os.path.join(d, "default")
            open(df, "w").write("# x\n#SKLADENOS_USER=mobian\n")
            run, calls = self.rec()
            log = account.process_pending_rename(run, d, df, users=["skladen"], groups=["skladen"])
            self.assertEqual([c[0][0] for c in calls], ["usermod", "usermod", "groupmod", "skladenos-apply"])
            self.assertEqual(calls[1][0], ["usermod", "-d", "/home/dima", "-m", "dima"])
            self.assertIn("SKLADENOS_USER=dima", open(df).read())
            self.assertFalse(os.path.exists(os.path.join(d, "rename-pending")))
            # имя занято -> пропуск без команд
            open(os.path.join(d, "rename-pending"), "w").write("skladen dima\n")
            run2, calls2 = self.rec()
            account.process_pending_rename(run2, d, df, users=["skladen", "dima"], groups=[])
            self.assertEqual(calls2, [])
            self.assertFalse(os.path.exists(os.path.join(d, "rename-pending")))

    def test_pending_failure_stops(self):
        with tempfile.TemporaryDirectory() as d:
            open(os.path.join(d, "rename-pending"), "w").write("skladen dima\n")
            run, calls = self.rec(8)
            account.process_pending_rename(run, d, os.path.join(d, "df"), users=["skladen"], groups=[])
            self.assertEqual(len(calls), 1)
            self.assertFalse(os.path.exists(os.path.join(d, "df")))


if __name__ == "__main__":
    unittest.main()
