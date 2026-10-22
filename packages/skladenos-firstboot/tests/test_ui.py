"""Тесты UI на демо-бэкендах (нужен python3-textual; без него пропускаются). Тап = клик мыши -> pilot.click."""
import asyncio, os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "files", "usr", "lib", "skladenos-firstboot"))
try:
    import textual  # noqa: F401
    HAVE = True
except ImportError:
    HAVE = False


class FakeOsk:
    def __init__(self): self.log = []; self.opened = False
    def show(self): self.log.append("show"); self.opened = True
    def hide(self): self.log.append("hide"); self.opened = False
    def toggle(self): self.hide() if self.opened else self.show()
    def is_open(self): return self.opened


async def vis(pilot, sel):
    """Прокрутить к виджету (в окне 84x19 строк, как на телефоне, кнопки не помещаются)."""
    w = pilot.app.screen.query_one(sel) if isinstance(sel, str) else sel
    w.scroll_visible(animate=False)
    await pilot.pause(0.1)
    return w


async def wait_for(pilot, cond, tries=60):
    for _ in range(tries):
        await pilot.pause(0.1)
        if cond():
            return True
    return False


@unittest.skipUnless(HAVE, "textual не установлен")
class UiFlow(unittest.IsolatedAsyncioTestCase):
    def make(self, **kw):
        from skladenos_firstboot.demo import DemoAccount, DemoBluetooth, DemoWifi
        from skladenos_firstboot.ui import Backends, FirstBootApp
        self.acc = DemoAccount()
        self.osk = FakeOsk()
        return FirstBootApp(Backends(DemoBluetooth(delay=0.2, **kw), DemoWifi(delay=0.1), self.acc, self.osk))

    async def test_full_flow_by_taps(self):
        app = self.make()
        async with app.run_test(size=(70, 60)) as pilot:
            # шаг 1: тап по клавиатуре в списке -> сопряжение
            self.assertTrue(await wait_for(pilot, lambda: len(app.screen.query("ListItem")) >= 2))
            await pilot.pause(0.5)  # список дорисован и не перестраивается
            kb = [i for i in app.screen.query("ListItem") if i.name == "AA:BB:CC:00:00:02"][0]
            await pilot.click(kb)
            self.assertTrue(await wait_for(pilot, lambda: app.has_bt_keyboard))
            await pilot.click("#skip")  # теперь «Далее»
            # шаг 2: сеть с паролем
            self.assertTrue(await wait_for(pilot, lambda: len(app.screen.query("#nets ListItem")) == 3))
            await pilot.click([i for i in app.screen.query("ListItem") if i.name == "Home-5G"][0])
            await pilot.pause(0.2)
            self.assertFalse(app.screen.query_one("#pw").has_class("hidden"))
            app.screen.query_one("#pw").value = "wrong"
            await pilot.click("#go")
            self.assertTrue(await wait_for(pilot, lambda: "пароль" in str(app.screen.query_one("#status").render()).lower()))
            app.screen.query_one("#pw").value = "password"
            await pilot.click("#go")
            self.assertTrue(await wait_for(pilot, lambda: "интернет есть" in str(app.screen.query_one("#status").render())))
            await pilot.click("#skip")
            # шаг 3
            from skladenos_firstboot.ui import AccountScreen, DoneScreen
            self.assertTrue(await wait_for(pilot, lambda: isinstance(app.screen, AccountScreen)))
            s = app.screen
            s.query_one("#user").value = "dima"
            s.query_one("#pw1").value = "1234"
            s.query_one("#pw2").value = "1234"
            await pilot.click("#save")
            await pilot.pause(0.2)
            self.assertIn("по умолчанию", str(s.query_one("#status").render()))
            self.assertEqual(self.acc.calls, [])
            s.query_one("#pw1").value = "s3cret!"
            s.query_one("#pw2").value = "s3cret!"
            await pilot.click("#save")
            self.assertTrue(await wait_for(pilot, lambda: isinstance(app.screen, DoneScreen)))
            self.assertEqual(self.acc.calls, [("dima", "s3cret!")])
            self.assertTrue(len(app.screen.query("#reboot")) == 1)
            await pilot.pause(0.5)  # раскладка нового экрана устоялась
            await pilot.click("#close")
            await wait_for(pilot, lambda: app._exit)  # run_test сам зовёт exit() на выходе и затёр бы результат
        self.assertEqual(app.return_value, 0)

    async def test_skip_everything_and_osk(self):
        app = self.make(present=False)
        async with app.run_test(size=(70, 60)) as pilot:
            await pilot.pause(0.3)
            self.assertIn("не найден", str(app.screen.query_one("#status").render()))
            await pilot.click("#skip")
            await pilot.pause(0.3)
            await pilot.click("#skip")
            from skladenos_firstboot.ui import AccountScreen
            self.assertTrue(await wait_for(pilot, lambda: isinstance(app.screen, AccountScreen)))
            app.screen.query_one("#pw1").focus()
            await pilot.pause(0.2)
            self.assertIn("show", self.osk.log)  # фокус на поле -> экранная клавиатура
            await pilot.press("f2")
            self.assertFalse(self.osk.opened)
            await pilot.click("#skip")
            await wait_for(pilot, lambda: app._exit)
        self.assertEqual(app.return_value, 2)

    async def test_bt_pair_failure_shown(self):
        app = self.make(fail_pair=True)
        async with app.run_test(size=(70, 60)) as pilot:
            self.assertTrue(await wait_for(pilot, lambda: len(app.screen.query("ListItem")) >= 2))
            await pilot.pause(0.5)
            await pilot.click([i for i in app.screen.query("ListItem") if i.name == "AA:BB:CC:00:00:02"][0])
            self.assertTrue(await wait_for(pilot, lambda: "AuthenticationFailed" in str(app.screen.query_one("#status").render())))
            self.assertFalse(app.has_bt_keyboard)

    async def test_list_not_rebuilt_and_selection_kept(self):
        """Обновление списка Bluetooth не пересоздаёт пункты: тот же объект, подсвеченный пункт сохраняется."""
        app = self.make()
        async with app.run_test(size=(84, 19)) as pilot:
            self.assertTrue(await wait_for(pilot, lambda: len(app.screen.query("ListItem")) >= 2))
            scr = app.screen
            before = {i.name: i for i in scr.query("ListItem")}
            lv = scr.query_one("#devs")
            lv.index = 1
            devs = list(scr.app.backends.bluetooth.devices())
            scr.shown = []  # принудительное обновление с переименованием
            app._last_touch = 0.0
            devs[0].name = devs[0].name + " (2)"
            scr.show_devices(devs)
            await pilot.pause(0.3)
            after = {i.name: i for i in scr.query("ListItem")}
            self.assertEqual({k: id(v) for k, v in before.items()}, {k: id(v) for k, v in after.items()})
            self.assertEqual(lv.index, 1)
            self.assertIn("(2)", str(after[devs[0].mac].query_one("Label").render()))
            # исчезновение устройства: удаляется только оно
            scr.shown = []
            scr.show_devices(devs[1:])
            await pilot.pause(0.3)
            self.assertEqual(sorted(i.name for i in scr.query("ListItem")), sorted(d.mac for d in devs[1:]))

    async def test_no_list_update_right_after_touch(self):
        app = self.make()
        async with app.run_test(size=(84, 19)) as pilot:
            self.assertTrue(await wait_for(pilot, lambda: len(app.screen.query("ListItem")) >= 2))
            scr = app.screen
            n = len(scr.query("ListItem"))
            scr.shown = []
            from textual import events
            await app.on_event(events.MouseDown(None, 3, 4, 0, 0, 1, False, False, False))  # как от драйвера
            scr.show_devices([])  # сразу после касания список не трогаем
            await pilot.pause(0.2)
            self.assertEqual(len(scr.query("ListItem")), n)

    async def test_tap_on_mouse_down_only_and_no_double(self):
        """Кнопка срабатывает на MouseDown ровно один раз (потом приходит Click и игнорируется)."""
        from skladenos_firstboot.ui import BluetoothScreen, TapButton, WifiScreen
        app = self.make(present=False)
        async with app.run_test(size=(84, 19)) as pilot:
            await pilot.pause(0.3)
            self.assertIsInstance(app.screen, BluetoothScreen)
            presses = []
            orig = TapButton.press
            TapButton.press = lambda self: (presses.append(self.id), orig(self))[1]
            try:
                await vis(pilot, "#skip"); await pilot.mouse_down("#skip")  # палец ещё не отпущен
                await pilot.pause(0.2)
                self.assertEqual(presses, ["skip"])
                await pilot.mouse_up()
                await pilot.pause(0.2)
                self.assertEqual(presses, ["skip"])
            finally:
                TapButton.press = orig
            self.assertTrue(await wait_for(pilot, lambda: isinstance(app.screen, WifiScreen)))

    async def test_item_selected_on_mouse_down_once(self):
        app = self.make()
        async with app.run_test(size=(84, 19)) as pilot:
            self.assertTrue(await wait_for(pilot, lambda: len(app.screen.query("ListItem")) >= 2))
            await pilot.pause(0.5)
            calls = []
            app.backends.bluetooth.pair = lambda mac, cb: (calls.append(mac), (False, "x"))[1]
            item = [i for i in app.screen.query("ListItem") if i.name == "AA:BB:CC:00:00:02"][0]
            await vis(pilot, item); await pilot.click(item, offset=(2, 0))  # верхний край пункта, не центр текста
            await pilot.pause(0.5)
            self.assertEqual(calls, ["AA:BB:CC:00:00:02"])

    async def test_input_retap_shows_osk_again(self):
        app = self.make(present=False)
        async with app.run_test(size=(84, 40)) as pilot:
            await pilot.click("#skip"); await pilot.pause(0.3)
            await pilot.click("#skip")
            from skladenos_firstboot.ui import AccountScreen
            self.assertTrue(await wait_for(pilot, lambda: isinstance(app.screen, AccountScreen)))
            await pilot.click("#pw1"); await pilot.pause(0.2)
            self.assertTrue(self.osk.opened)
            self.osk.hide()  # «Скрыть клавиатуру»; фокус остаётся на поле
            await pilot.click("#pw1"); await pilot.pause(0.2)
            self.assertTrue(self.osk.opened)

    async def test_touch_geometry(self):
        """Цели касания крупные: кнопки >= 5 строк, пункты списка >= 4, зазор между кнопками >= 1."""
        app = self.make()
        async with app.run_test(size=(84, 19)) as pilot:
            self.assertTrue(await wait_for(pilot, lambda: len(app.screen.query("ListItem")) >= 2))
            for b in app.screen.query("Button"):
                self.assertGreaterEqual(b.outer_size.height, 5)
                self.assertGreaterEqual(b.styles.margin.top, 1)
            for i in app.screen.query("ListItem"):
                self.assertGreaterEqual(i.styles.height.value, 4)

    async def test_taplog(self):
        import tempfile
        from textual import events
        log = tempfile.mktemp()
        os.environ["SKLADENOS_FIRSTBOOT_TAPLOG"] = log
        try:
            app = self.make(present=False)
            async with app.run_test(size=(84, 19)) as pilot:
                await pilot.pause(0.2)
                await app.on_event(events.MouseDown(None, 3, 4, 0, 0, 1, False, False, False))
                await app.on_event(events.MouseUp(None, 3, 4, 0, 0, 1, False, False, False))
            txt = open(log).read()
            self.assertIn("MouseDown x=3 y=4", txt)
            self.assertIn("MouseUp", txt)
            self.assertTrue(app.touch_recent())
        finally:
            os.environ.pop("SKLADENOS_FIRSTBOOT_TAPLOG", None)
            if os.path.exists(log): os.unlink(log)


if __name__ == "__main__":
    unittest.main()
