"""Пользователь и пароль: проверка ввода, применение от root (helper), отложенное переименование.

Переименовать вошедшего пользователя на лету нельзя (usermod -l отказывает, пока у него есть процессы,
а sway/мастер работают от него), поэтому: пароль меняется сразу, переименование записывается в
rename-pending и выполняется на следующей загрузке юнитом skladenos-firstboot-rename до sxmo.service.
"""
from __future__ import annotations

import json
import os
import pwd
import re
import subprocess
from typing import Callable, Iterable, Optional

from . import FLAG_NAME, PENDING_NAME, STATE_DIR

DEFAULT_USER = "skladen"
DEFAULT_PASSWORD = "1234"
MIN_PASSWORD = 6
HELPER = "/usr/lib/skladenos-firstboot/helper"
USERNAME_RE = re.compile(r"^[a-z_][a-z0-9_-]{0,30}$")
RESERVED = {"root", "daemon", "bin", "sys", "sync", "games", "man", "lp", "mail", "news", "uucp", "proxy",
            "www-data", "backup", "list", "irc", "nobody", "sshd", "systemd-network", "messagebus"}

# Runner: (args, input) -> (returncode, output)
Runner = Callable[[list, Optional[str]], tuple]


def validate_username(name: str, taken: Iterable[str] = (), current: str = "") -> Optional[str]:
    """None, если имя годится; иначе текст ошибки по-русски."""
    if not name:
        return "Введите имя пользователя"
    if not USERNAME_RE.match(name):
        return "Имя: строчные латинские буквы, цифры, - и _, начинается с буквы (до 31 символа)"
    if name in RESERVED:
        return "Это системное имя, выберите другое"
    if name != current and name in set(taken):
        return "Такой пользователь уже есть"
    return None


def validate_password(pw: str, confirm: Optional[str] = None) -> Optional[str]:
    if pw == DEFAULT_PASSWORD:
        return "Пароль по умолчанию менять нужно: выберите другой"
    if len(pw) < MIN_PASSWORD:
        return "Пароль слишком короткий (минимум %d символов)" % MIN_PASSWORD
    if any(ord(c) < 32 or ord(c) == 127 for c in pw):
        return "В пароле недопустимые символы"
    if confirm is not None and pw != confirm:
        return "Пароли не совпадают"
    return None


def system_users() -> list[str]:
    return [p.pw_name for p in pwd.getpwall()]


def default_runner(args, input=None):
    p = subprocess.run(args, input=input, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def flag_path(state_dir: str = STATE_DIR) -> str:
    return os.path.join(state_dir, FLAG_NAME)


def is_done(state_dir: str = STATE_DIR) -> bool:
    return os.path.exists(flag_path(state_dir))


def apply_changes(current: str, new_user: str, password: str, runner: Runner = default_runner,
                  state_dir: str = STATE_DIR, taken: Optional[Iterable[str]] = None) -> dict:
    """Работа helper'а (root). Возвращает {'ok', 'error', 'rename_pending'}. Флаг firstboot-done ставится в конце."""
    if is_done(state_dir):
        return {"ok": False, "error": "Мастер уже пройден"}
    taken = system_users() if taken is None else list(taken)
    err = validate_username(new_user, taken, current) or validate_password(password)
    if err:
        return {"ok": False, "error": err}
    rc, out = runner(["chpasswd"], "%s:%s\n" % (current, password))
    if rc != 0:
        return {"ok": False, "error": "chpasswd: " + out.strip()}
    rename = new_user != current
    os.makedirs(state_dir, exist_ok=True)
    if rename:
        with open(os.path.join(state_dir, PENDING_NAME), "w") as f:
            f.write("%s %s\n" % (current, new_user))
    with open(flag_path(state_dir), "w") as f:
        f.write("done\n")
    return {"ok": True, "rename_pending": rename}


def process_pending_rename(runner: Runner = default_runner, state_dir: str = STATE_DIR,
                           default_file: str = "/etc/default/skladenos", users: Optional[Iterable[str]] = None,
                           groups: Optional[Iterable[str]] = None) -> list[str]:
    """Загрузочный шаг (root, до sxmo.service). Возвращает журнал; файл rename-pending удаляется всегда."""
    path = os.path.join(state_dir, PENDING_NAME)
    log: list[str] = []
    if not os.path.exists(path):
        return log
    try:
        old, new = open(path).read().split()
    except ValueError:
        os.remove(path)
        return ["rename-pending повреждён"]
    users = set(system_users() if users is None else users)
    if groups is None:
        try:
            import grp
            groups = [g.gr_name for g in grp.getgrall()]
        except Exception:
            groups = []
    groups = set(groups)
    if old not in users or new in users or validate_username(new, (), "") is not None:
        os.remove(path)
        return ["пропуск: %s -> %s невозможно" % (old, new)]
    steps = [["usermod", "-l", new, old], ["usermod", "-d", "/home/" + new, "-m", new]]
    if old in groups and new not in groups:
        steps.append(["groupmod", "-n", new, old])
    ok = True
    for s in steps:
        rc, out = runner(s, None)
        log.append("%s -> %d %s" % (" ".join(s), rc, out.strip()))
        if rc != 0:
            ok = False
            break
    if ok:
        _set_default_user(default_file, new)
        # пути вида /home/<old> в ~/.config/sxmo -> пересобрать под нового пользователя
        rc, out = runner(["skladenos-apply", "--user", new, "--force"], None)
        log.append("skladenos-apply -> %d" % rc)
    os.remove(path)
    return log


def _set_default_user(default_file: str, new: str) -> None:
    try:
        text = open(default_file).read()
    except FileNotFoundError:
        text = ""
    line = "SKLADENOS_USER=%s" % new
    if re.search(r"(?m)^#?\s*SKLADENOS_USER=", text):
        text = re.sub(r"(?m)^#?\s*SKLADENOS_USER=.*$", line, text, count=1)
    else:
        text += ("\n" if text and not text.endswith("\n") else "") + line + "\n"
    os.makedirs(os.path.dirname(default_file), exist_ok=True)
    with open(default_file, "w") as f:
        f.write(text)


class AccountBackend:
    def current_user(self) -> str: raise NotImplementedError
    def taken_names(self) -> list: raise NotImplementedError
    def apply(self, new_user: str, password: str) -> dict: raise NotImplementedError


class SudoHelperBackend(AccountBackend):
    """Зовёт root-helper через `sudo -n`; пароль только в stdin."""

    def __init__(self, helper: str = HELPER):
        self.helper = helper

    def current_user(self):
        return pwd.getpwuid(os.getuid()).pw_name

    def taken_names(self):
        return system_users()

    def apply(self, new_user, password):
        payload = json.dumps({"username": new_user, "password": password})
        try:
            p = subprocess.run(["sudo", "-n", self.helper], input=payload, capture_output=True, text=True, timeout=60)
        except Exception as e:  # noqa: BLE001
            return {"ok": False, "error": str(e)}
        try:
            return json.loads(p.stdout.strip().splitlines()[-1])
        except (IndexError, ValueError):
            return {"ok": False, "error": (p.stderr or p.stdout or "helper не ответил").strip()}
