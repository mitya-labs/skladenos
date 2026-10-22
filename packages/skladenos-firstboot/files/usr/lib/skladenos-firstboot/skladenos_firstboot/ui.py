"""TUI мастера первой загрузки (Textual). Весь ввод-вывод с системой идёт через бэкенды."""
from __future__ import annotations

import os
import time
from dataclasses import dataclass
from typing import Optional

from textual import events, work
from textual.app import App, ComposeResult
from textual.containers import VerticalScroll
from textual.screen import Screen
from textual.widgets import Button, Input, Label, ListItem, ListView, Static

from . import account as acc
from .account import AccountBackend
from .bluetooth import BluetoothBackend
from .osk import Osk
from .wifi import WifiBackend

CSS = """
Screen { background: $surface; }
VerticalScroll { padding: 1 2; }
.title { text-style: bold; color: $accent; margin-bottom: 1; }
.status { margin: 1 0; min-height: 2; }
.err { color: $error; }
.ok { color: $success; }
Button { width: 100%; height: 5; min-height: 5; margin: 1 0 0 0; }
ListView { height: auto; max-height: 24; margin: 1 0; border: round $primary; }
ListItem { height: 4; padding: 0 1; border-bottom: hkey $primary 50%; }
ListItem Label { width: 100%; height: 100%; content-align: left middle; }
ListItem.-highlight { background: $accent 40%; }
Input { height: 5; margin: 1 0 0 0; }
.hidden { display: none; }
"""


class TapButton(Button):
    """Кнопка, срабатывающая на касание (MouseDown), а не на Click.

    Click в Textual засчитывается, только если MouseDown и MouseUp пришлись на один виджет;
    при касании пальцем foot шлёт нажатие и отпускание подряд, но на смене раскладки между ними
    (перерисовка списка, прокрутка) клик теряется. Срабатывание на нажатие этого не боится.
    """

    def on_mouse_down(self, event: events.MouseDown) -> None:
        event.stop()
        if event.button == 1 and not self.has_class("-active"):
            self.press()

    def on_click(self, event: events.Click) -> None:
        event.prevent_default()  # уже сработали на MouseDown; штатный _on_click не звать
        event.stop()


class TapItem(ListItem):
    """Пункт списка, выбираемый касанием (MouseDown) по любой точке, включая отступы."""

    def on_mouse_down(self, event: events.MouseDown) -> None:
        event.stop()
        lv = self.parent
        if event.button != 1 or not isinstance(lv, ListView):
            return
        lv.focus()
        lv.index = list(lv.children).index(self)
        lv.post_message(ListView.Selected(lv, self, lv.index))

    def on_click(self, event: events.Click) -> None:
        event.prevent_default()  # выбор уже сделан на MouseDown
        event.stop()


class TapInput(Input):
    """Поле ввода: повторное касание уже сфокусированного поля снова показывает экранную клавиатуру."""

    def on_mouse_down(self, event: events.MouseDown) -> None:
        app = self.app
        if not getattr(app, "has_bt_keyboard", False):
            app.osk.show()


def sync_list(lv: ListView, rows: "list[tuple[str, str]]", cache: dict) -> None:
    """Привести ListView к rows [(ключ, текст)] без пересоздания: порядок существующих пунктов
    сохраняется, новые добавляются в конец, пропавшие удаляются, текст меняется на месте.
    Так список не «прыгает» под пальцем и выбранный пункт остаётся тем же."""
    want = dict(rows)
    gone = [i for i, it in enumerate(lv.children) if it.name not in want]
    for k in [k for k in cache if k not in want]:
        del cache[k]
    if gone:
        lv.remove_items(gone)
    for key, text in rows:
        if key in cache:
            cache[key].query_one(Label).update(text)
        else:
            cache[key] = TapItem(Label(text), name=key)
            lv.append(cache[key])


@dataclass
class Backends:
    bluetooth: BluetoothBackend
    wifi: WifiBackend
    account: AccountBackend
    osk: Osk


class StepScreen(Screen):
    """Общая часть: показ экранной клавиатуры при фокусе на поле ввода."""

    def on_descendant_focus(self, event) -> None:
        if isinstance(event.widget, Input) and not self.app.has_bt_keyboard:
            self.app.osk.show()

    def on_screen_suspend(self) -> None:
        self.app.osk.hide()

    def set_status(self, text: str, cls: str = "") -> None:
        w = self.query_one("#status", Static)
        w.remove_class("err", "ok")
        if cls:
            w.add_class(cls)
        w.update(text)

    def key_escape(self) -> None:
        self.app.osk.hide()


class BluetoothScreen(StepScreen):
    def compose(self) -> ComposeResult:
        with VerticalScroll():
            yield Label("Шаг 1 из 3. Bluetooth-клавиатура", classes="title")
            yield Static("Включите клавиатуру в режим сопряжения и выберите её из списка.", id="hint")
            yield Static("Поиск...", id="status", classes="status")
            yield ListView(id="devs")
            yield TapButton("Искать заново", id="rescan")
            yield TapButton("Пропустить, у меня нет клавиатуры", id="skip", variant="primary")

    def on_mount(self) -> None:
        self.shown: list = []
        self.items: dict = {}
        self.busy = False
        self.sticky = False  # итог сопряжения не затирать статусом списка
        self.start()

    @work(thread=True, exclusive=True, group="bt-scan")
    def start(self) -> None:
        bt = self.app.backends.bluetooth
        ok, why = bt.available()
        if not ok:
            self.app.call_from_thread(self.set_status, why + ". Шаг можно пропустить.", "err")
            return
        bt.start_scan()
        import time
        for _ in range(40):
            if self.busy:
                time.sleep(0.5)
                continue
            devs = bt.devices()
            self.app.call_from_thread(self.show_devices, devs)
            time.sleep(1.5)
            if not self.is_attached:
                return

    def show_devices(self, devs) -> None:
        key = [(d.mac, d.name, d.is_keyboard, d.connected) for d in devs]
        if key == self.shown or self.busy or self.app.touch_recent():
            return  # не трогать список под пальцем; следующий опрос повторит
        self.shown = key
        sync_list(self.query_one("#devs", ListView),
                  [(d.mac, ("* " if d.connected else "") + ("[клавиатура] " if d.is_keyboard else "") + d.name)
                   for d in devs], self.items)
        if not self.sticky:
            self.set_status("Найдено устройств: %d. Нажмите на клавиатуру в списке." % len(devs) if devs else "Поиск устройств...")

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        if self.busy:
            return
        self.pair(event.item.name)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "rescan":
            self.shown = []
            self.sticky = False
            self.start()
        else:
            self.app.next_step()

    @work(thread=True, exclusive=True, group="bt-pair")
    def pair(self, mac: str) -> None:
        self.busy = True

        def on_event(kind: str, text: str) -> None:
            msg = {"passkey": "Введите на Bluetooth-клавиатуре код %s и нажмите Enter" % text,
                   "passkey_confirm": "Подтверждение кода %s..." % text,
                   "pin_request": "Используется PIN 0000. Если не подойдёт, введите 0000 и Enter на клавиатуре",
                   "status": text}.get(kind, text)
            self.app.call_from_thread(self.set_status, msg)

        ok, msg = self.app.backends.bluetooth.pair(mac, on_event)
        self.sticky = True
        self.busy = False
        if ok:
            self.app.has_bt_keyboard = True
            self.app.call_from_thread(self.done_ok)
        else:
            self.app.call_from_thread(self.set_status, msg, "err")

    def done_ok(self) -> None:
        self.set_status("Клавиатура подключена. Дальше можно печатать на ней.", "ok")
        self.query_one("#skip", Button).label = "Далее"
        self.app.osk.hide()


class WifiScreen(StepScreen):
    def compose(self) -> ComposeResult:
        with VerticalScroll():
            yield Label("Шаг 2 из 3. Wi-Fi", classes="title")
            yield Static("Поиск сетей...", id="status", classes="status")
            yield Static("", id="chosen")
            yield TapInput(placeholder="Пароль сети", password=True, id="pw", classes="hidden")
            yield TapButton("Показать/скрыть пароль", id="showpw", classes="hidden")
            yield TapButton("Подключиться", id="go", variant="success", classes="hidden")
            yield TapButton("Скрыть клавиатуру", id="hidekb", classes="hidden")
            yield ListView(id="nets")
            yield TapButton("Обновить список", id="rescan")
            yield TapButton("Пропустить Wi-Fi", id="skip", variant="primary")

    def on_mount(self) -> None:
        self.ssid: Optional[str] = None
        self.items: dict = {}
        self.nets: dict = {}
        self.busy = False
        self.scan()

    @work(thread=True, exclusive=True, group="wifi-scan")
    def scan(self) -> None:
        wifi = self.app.backends.wifi
        ok, why = wifi.available()
        if not ok:
            self.app.call_from_thread(self.set_status, why + ". Шаг можно пропустить.", "err")
            return
        self.app.call_from_thread(self.set_status, "Поиск сетей...")
        nets = wifi.scan()
        self.app.call_from_thread(self.show_nets, nets)

    def show_nets(self, nets) -> None:
        self.nets = {n.ssid: n for n in nets}
        sync_list(self.query_one("#nets", ListView),
                  [(n.ssid, "%s%s  %d%%%s" % ("* " if n.in_use else "", n.ssid, n.signal,
                                              "  [пароль]" if n.secured else "")) for n in nets], self.items)
        self.set_status("Выберите сеть." if nets else "Сети не найдены. Обновите список или пропустите шаг.")

    def panel(self, show: bool) -> None:
        for i in ("pw", "showpw", "go", "hidekb"):
            self.query_one("#" + i).set_class(not show, "hidden")

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        if self.busy:
            return
        self.ssid = event.item.name
        net = self.nets.get(self.ssid)
        self.query_one("#chosen", Static).update("Сеть: %s" % self.ssid)
        if net and net.secured:
            self.panel(True)
            self.query_one("#pw", Input).value = ""
            self.query_one("#pw", Input).focus()
            self.set_status("Введите пароль и нажмите «Подключиться».")
        else:
            self.panel(False)
            self.connect("")

    def on_input_submitted(self, event: Input.Submitted) -> None:
        self.on_button_pressed_id("go")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.on_button_pressed_id(event.button.id)

    def on_button_pressed_id(self, bid: str) -> None:
        if bid == "rescan":
            self.scan()
        elif bid == "showpw":
            pw = self.query_one("#pw", Input)
            pw.password = not pw.password
        elif bid == "hidekb":
            self.app.osk.hide()
        elif bid == "go" and self.ssid and not self.busy:
            self.app.osk.hide()
            self.connect(self.query_one("#pw", Input).value)
        elif bid == "skip":
            self.app.next_step()

    @work(thread=True, exclusive=True, group="wifi-connect")
    def connect(self, password: str) -> None:
        self.busy = True
        self.app.call_from_thread(self.set_status, "Подключение к %s..." % self.ssid)
        ok, msg = self.app.backends.wifi.connect(self.ssid, password)
        self.busy = False
        if ok:
            self.app.call_from_thread(self.on_connected, msg)
        else:
            self.app.call_from_thread(self.set_status, msg, "err")

    def on_connected(self, msg: str) -> None:
        self.panel(False)
        self.set_status(msg, "ok")
        self.query_one("#skip", Button).label = "Далее"


class AccountScreen(StepScreen):
    def compose(self) -> ComposeResult:
        cur = self.app.backends.account.current_user()
        with VerticalScroll():
            yield Label("Шаг 3 из 3. Пользователь и пароль", classes="title")
            yield Static("Имя пользователя можно оставить или сменить. Пароль по умолчанию (%s) нужно сменить; "
                         "до этого SSH-вход по паролю открыт только из локальных сетей." % acc.DEFAULT_PASSWORD)
            yield TapInput(value=cur, placeholder="Имя пользователя", id="user")
            yield TapInput(placeholder="Новый пароль", password=True, id="pw1")
            yield TapInput(placeholder="Повторите пароль", password=True, id="pw2")
            yield Static("", id="status", classes="status")
            yield TapButton("Показать/скрыть пароль", id="showpw")
            yield TapButton("Скрыть клавиатуру", id="hidekb")
            yield TapButton("Сохранить", id="save", variant="success")
            yield TapButton("Пропустить (мастер запустится снова)", id="skip")

    def on_mount(self) -> None:
        self.busy = False

    def on_input_submitted(self, event: Input.Submitted) -> None:
        order = ["user", "pw1", "pw2"]
        i = order.index(event.input.id)
        if i < 2:
            self.query_one("#" + order[i + 1]).focus()
        else:
            self.save()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        bid = event.button.id
        if bid == "showpw":
            for i in ("pw1", "pw2"):
                w = self.query_one("#" + i, Input)
                w.password = not w.password
        elif bid == "hidekb":
            self.app.osk.hide()
        elif bid == "save":
            self.save()
        elif bid == "skip":
            self.app.exit(2)

    def save(self) -> None:
        if self.busy:
            return
        be = self.app.backends.account
        user = self.query_one("#user", Input).value.strip()
        p1, p2 = self.query_one("#pw1", Input).value, self.query_one("#pw2", Input).value
        err = acc.validate_username(user, be.taken_names(), be.current_user()) or acc.validate_password(p1, p2)
        if err:
            self.set_status(err, "err")
            return
        self.app.osk.hide()
        self.busy = True
        self.set_status("Сохранение...")
        self.apply(user, p1)

    @work(thread=True, exclusive=True, group="account")
    def apply(self, user: str, pw: str) -> None:
        res = self.app.backends.account.apply(user, pw)
        self.busy = False
        if res.get("ok"):
            self.app.call_from_thread(self.app.finish, user, bool(res.get("rename_pending")))
        else:
            self.app.call_from_thread(self.set_status, res.get("error", "Ошибка"), "err")


class DoneScreen(StepScreen):
    def __init__(self, user: str, rename_pending: bool):
        super().__init__()
        self.user, self.rename = user, rename_pending

    def compose(self) -> ComposeResult:
        with VerticalScroll():
            yield Label("Готово", classes="title")
            yield Static("Пароль изменён." + (
                "\nИмя пользователя «%s» применится после перезагрузки (до неё вход по прежнему имени)." % self.user
                if self.rename else ""), classes="status ok", id="status")
            if self.rename:
                yield TapButton("Перезагрузить сейчас", id="reboot", variant="success")
            yield TapButton("Закрыть мастер", id="close", variant="primary")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "reboot":
            self.app.exit(10)  # launcher выполняет перезагрузку
        else:
            self.app.exit(0)


class FirstBootApp(App):
    CSS = CSS
    ALLOW_SELECT = False  # выделение текста не нужно; длинное касание foot (drag) не должно его начинать
    TITLE = "skladenOS: первая загрузка"
    BINDINGS = [("ctrl+k", "toggle_osk", "Клавиатура"), ("f2", "toggle_osk", "Клавиатура")]

    def __init__(self, backends: Backends):
        super().__init__()
        self.backends = backends
        self.osk = backends.osk
        self.has_bt_keyboard = False
        self._steps = [BluetoothScreen, WifiScreen, AccountScreen]
        self._i = -1
        self._last_touch = 0.0
        self._taplog = os.environ.get("SKLADENOS_FIRSTBOOT_TAPLOG")

    def touch_recent(self, within: float = 1.0) -> bool:
        """Было ли касание/прокрутка за последние within секунд (тогда списки не перерисовываем)."""
        return time.monotonic() - self._last_touch < within

    async def on_event(self, event) -> None:
        if isinstance(event, (events.MouseDown, events.MouseUp, events.MouseScrollUp, events.MouseScrollDown)):
            self._last_touch = time.monotonic()
            if self._taplog and not event.is_forwarded:  # диагностика сенсора: что реально дошло до Textual
                try:
                    with open(self._taplog, "a") as f:
                        f.write("%.3f %s x=%d y=%d button=%s\n" % (
                            time.time(), type(event).__name__, event.x, event.y, getattr(event, "button", "")))
                except OSError:
                    pass
        await super().on_event(event)

    def on_mount(self) -> None:
        self.next_step()

    def next_step(self) -> None:
        self._i += 1
        self.osk.hide()
        if self._i < len(self._steps):
            self.push_screen(self._steps[self._i]())

    def action_toggle_osk(self) -> None:
        self.osk.toggle()

    def finish(self, user: str, rename_pending: bool) -> None:
        self.push_screen(DoneScreen(user, rename_pending))

    def on_unmount(self) -> None:
        try:
            self.backends.bluetooth.stop()
        except Exception:  # noqa: BLE001
            pass
        self.osk.hide()
