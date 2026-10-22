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
            await pilot.click("#close")
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
        self.assertEqual(app.return_value, 2)

    async def test_bt_pair_failure_shown(self):
        app = self.make(fail_pair=True)
        async with app.run_test(size=(70, 60)) as pilot:
            self.assertTrue(await wait_for(pilot, lambda: len(app.screen.query("ListItem")) >= 2))
            await pilot.pause(0.5)
            await pilot.click([i for i in app.screen.query("ListItem") if i.name == "AA:BB:CC:00:00:02"][0])
            self.assertTrue(await wait_for(pilot, lambda: "AuthenticationFailed" in str(app.screen.query_one("#status").render())))
            self.assertFalse(app.has_bt_keyboard)


if __name__ == "__main__":
    unittest.main()
