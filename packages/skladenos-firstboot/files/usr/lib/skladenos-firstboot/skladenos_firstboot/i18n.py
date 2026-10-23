"""Переводы интерфейса мастера: словарь ключ -> {язык: текст}, язык по умолчанию en.

t(key, *args) берёт текст на текущем языке (нет перевода -> английский -> сам ключ) и подставляет args через %.
Бэкенды тоже зовут t(), поэтому сообщения об ошибках следуют выбранному языку.
Выбранный язык запоминается в ~/.config/skladenos/lang и подхватывается при следующем запуске мастера.
"""
from __future__ import annotations

import os

LANGS = {"en": "English", "ru": "Русский"}  # дополняется из langs.py
DEFAULT = "en"
_lang = DEFAULT


def config_path() -> str:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "skladenos", "lang")


def get_lang() -> str:
    return _lang


def set_lang(lang: str) -> None:
    global _lang
    _lang = lang if lang in LANGS else DEFAULT


def load_saved() -> bool:
    """Подхватить сохранённый язык; True, если он был сохранён."""
    try:
        with open(config_path()) as f:
            lang = f.read().strip()
    except OSError:
        return False
    if lang not in LANGS:
        return False
    set_lang(lang)
    return True


def save() -> None:
    try:
        os.makedirs(os.path.dirname(config_path()), exist_ok=True)
        with open(config_path(), "w") as f:
            f.write(_lang + "\n")
    except OSError:
        pass


def t(key: str, *args) -> str:
    entry = STRINGS.get(key)
    if entry is None:
        return key
    text = entry.get(_lang) or entry["en"]
    return text % args if args else text


STRINGS: dict[str, dict[str, str]] = {
    # --- общие ---
    "app.title": {"en": "skladenOS: first boot", "ru": "skladenOS: первая загрузка"},
    "lang.button": {"en": "Language / Язык", "ru": "Language / Язык"},
    "next": {"en": "Next", "ru": "Далее"},
    "hide_kb": {"en": "Hide keyboard", "ru": "Скрыть клавиатуру"},
    "show_pw": {"en": "Show/hide password", "ru": "Показать/скрыть пароль"},
    # --- шаг 0: язык ---
    "lang.title": {"en": "Language / Язык", "ru": "Language / Язык"},  # во всех языках одинаково
    "lang.hint": {"en": "Choose the language of this wizard. You can switch it later with the button on any step.",
                  "ru": "Выберите язык мастера. Его можно сменить кнопкой на любом шаге."},
    # --- шаг 1: Bluetooth ---
    "bt.title": {"en": "Step 1 of 3. Bluetooth keyboard", "ru": "Шаг 1 из 3. Bluetooth-клавиатура"},
    "bt.hint": {"en": "Put the keyboard into pairing mode and pick it from the list.",
                "ru": "Включите клавиатуру в режим сопряжения и выберите её из списка."},
    "bt.searching": {"en": "Searching...", "ru": "Поиск..."},
    "bt.rescan": {"en": "Search again", "ru": "Искать заново"},
    "bt.skip": {"en": "Skip, I have no keyboard", "ru": "Пропустить, у меня нет клавиатуры"},
    "bt.skippable": {"en": "%s. This step can be skipped.", "ru": "%s. Шаг можно пропустить."},
    "bt.keyboard_tag": {"en": "[keyboard] ", "ru": "[клавиатура] "},
    "bt.found": {"en": "Devices found: %d. Tap your keyboard in the list.",
                 "ru": "Найдено устройств: %d. Нажмите на клавиатуру в списке."},
    "bt.searching_devices": {"en": "Searching for devices...", "ru": "Поиск устройств..."},
    "bt.passkey": {"en": "Type %s on the Bluetooth keyboard and press Enter",
                   "ru": "Введите на Bluetooth-клавиатуре код %s и нажмите Enter"},
    "bt.passkey_confirm": {"en": "Confirming code %s...", "ru": "Подтверждение кода %s..."},
    "bt.pin_request": {"en": "Using PIN 0000. If it does not work, type 0000 and Enter on the keyboard",
                       "ru": "Используется PIN 0000. Если не подойдёт, введите 0000 и Enter на клавиатуре"},
    "bt.connected_kb": {"en": "Keyboard connected. You can type on it now.",
                        "ru": "Клавиатура подключена. Дальше можно печатать на ней."},
    "bt.no_bluetoothctl": {"en": "bluetoothctl not found", "ru": "bluetoothctl не найден"},
    "bt.no_adapter": {"en": "Bluetooth adapter not found", "ru": "Bluetooth-адаптер не найден"},
    "bt.pairing": {"en": "Pairing...", "ru": "Сопряжение..."},
    "bt.pair_timeout": {"en": "Pairing timed out", "ru": "Время ожидания сопряжения истекло"},
    "bt.pair_failed": {"en": "Pairing failed: %s", "ru": "Не удалось сопрячь: %s"},
    "bt.connecting": {"en": "Connecting...", "ru": "Подключение..."},
    "bt.connect_failed": {"en": "Could not connect", "ru": "Не удалось подключить"},
    "bt.connect_timeout": {"en": " (timed out)", "ru": " (время вышло)"},
    "bt.connected": {"en": "Connected", "ru": "Подключено"},
    # --- шаг 2: Wi-Fi ---
    "wifi.title": {"en": "Step 2 of 3. Wi-Fi", "ru": "Шаг 2 из 3. Wi-Fi"},
    "wifi.searching": {"en": "Searching for networks...", "ru": "Поиск сетей..."},
    "wifi.password": {"en": "Network password", "ru": "Пароль сети"},
    "wifi.connect": {"en": "Connect", "ru": "Подключиться"},
    "wifi.refresh": {"en": "Refresh list", "ru": "Обновить список"},
    "wifi.skip": {"en": "Skip Wi-Fi", "ru": "Пропустить Wi-Fi"},
    "wifi.secured_tag": {"en": "  [password]", "ru": "  [пароль]"},
    "wifi.choose": {"en": "Choose a network.", "ru": "Выберите сеть."},
    "wifi.none": {"en": "No networks found. Refresh the list or skip this step.",
                  "ru": "Сети не найдены. Обновите список или пропустите шаг."},
    "wifi.network": {"en": "Network: %s", "ru": "Сеть: %s"},
    "wifi.enter_pw": {"en": "Enter the password and tap “Connect”.", "ru": "Введите пароль и нажмите «Подключиться»."},
    "wifi.connecting": {"en": "Connecting to %s...", "ru": "Подключение к %s..."},
    "wifi.bad_pw": {"en": "Wrong password or authentication failed",
                    "ru": "Неверный пароль или не удалось пройти проверку"},
    "wifi.not_found": {"en": "Network not found (too far away?)", "ru": "Сеть не найдена (слишком далеко?)"},
    "wifi.timeout": {"en": "Connection timed out", "ru": "Время ожидания подключения истекло"},
    "wifi.no_rights": {"en": "Not allowed to manage Wi-Fi", "ru": "Нет прав управлять Wi-Fi"},
    "wifi.failed": {"en": "Could not connect", "ru": "Не удалось подключиться"},
    "wifi.no_nmcli": {"en": "nmcli not found", "ru": "nmcli не найден"},
    "wifi.no_nm": {"en": "NetworkManager is unavailable", "ru": "NetworkManager недоступен"},
    "wifi.no_adapter": {"en": "Wi-Fi adapter not found", "ru": "Wi-Fi адаптер не найден"},
    "wifi.ok_internet": {"en": "Connected, internet is available", "ru": "Подключено, интернет есть"},
    "wifi.ok_portal": {"en": "Connected, but the network requires a browser login",
                       "ru": "Подключено, но сеть требует вход через браузер"},
    "wifi.ok_no_internet": {"en": "Connected, but there is no internet access",
                            "ru": "Подключено, но доступа в интернет нет"},
    # --- шаг 3: пользователь ---
    "acc.title": {"en": "Step 3 of 3. User and password", "ru": "Шаг 3 из 3. Пользователь и пароль"},
    "acc.hint": {"en": "You can keep the user name or change it. The default password (%s) must be changed; "
                       "until then SSH password login is open only from local networks.",
                 "ru": "Имя пользователя можно оставить или сменить. Пароль по умолчанию (%s) нужно сменить; "
                       "до этого SSH-вход по паролю открыт только из локальных сетей."},
    "acc.user": {"en": "User name", "ru": "Имя пользователя"},
    "acc.pw1": {"en": "New password", "ru": "Новый пароль"},
    "acc.pw2": {"en": "Repeat password", "ru": "Повторите пароль"},
    "acc.save": {"en": "Save", "ru": "Сохранить"},
    "acc.skip": {"en": "Skip (the wizard will start again)", "ru": "Пропустить (мастер запустится снова)"},
    "acc.saving": {"en": "Saving...", "ru": "Сохранение..."},
    "acc.error": {"en": "Error", "ru": "Ошибка"},
    "acc.enter_name": {"en": "Enter a user name", "ru": "Введите имя пользователя"},
    "acc.bad_name": {"en": "Name: lowercase Latin letters, digits, - and _, must start with a letter (up to 31 characters)",
                     "ru": "Имя: строчные латинские буквы, цифры, - и _, начинается с буквы (до 31 символа)"},
    "acc.reserved": {"en": "This is a system name, choose another", "ru": "Это системное имя, выберите другое"},
    "acc.taken": {"en": "This user already exists", "ru": "Такой пользователь уже есть"},
    "acc.default_pw": {"en": "The default password must be changed: choose another",
                       "ru": "Пароль по умолчанию менять нужно: выберите другой"},
    "acc.short_pw": {"en": "Password is too short (at least %d characters)",
                     "ru": "Пароль слишком короткий (минимум %d символов)"},
    "acc.bad_chars": {"en": "The password contains invalid characters", "ru": "В пароле недопустимые символы"},
    "acc.mismatch": {"en": "Passwords do not match", "ru": "Пароли не совпадают"},
    "acc.already_done": {"en": "The wizard has already been completed", "ru": "Мастер уже пройден"},
    "acc.helper_silent": {"en": "helper did not respond", "ru": "helper не ответил"},
    # --- готово ---
    "done.title": {"en": "Done", "ru": "Готово"},
    "done.pw_changed": {"en": "Password changed.", "ru": "Пароль изменён."},
    "done.rename": {"en": "\nThe user name “%s” will take effect after a reboot (until then, log in with the old name).",
                    "ru": "\nИмя пользователя «%s» применится после перезагрузки (до неё вход по прежнему имени)."},
    "done.reboot": {"en": "Reboot now", "ru": "Перезагрузить сейчас"},
    "done.close": {"en": "Close wizard", "ru": "Закрыть мастер"},
}


def _merge_extra() -> None:
    from . import langs, langs_more
    for mod in (langs, langs_more):
        LANGS.update(mod.NAMES)
        for lang, tr in mod.TRANSLATIONS.items():
            for key, text in tr.items():
                STRINGS[key][lang] = text


_merge_extra()
