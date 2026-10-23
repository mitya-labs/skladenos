#!/usr/bin/env python3
"""Виртуальный тачскрин (uinput) для воспроизведения тапов и свайпов без пальца. Запускать от root на телефоне.
  fake-touch.py tap X Y | swipe X1 Y1 X2 Y2 [мс] | seq   # координаты 0..1000 по обеим осям (доля экрана)
seq: тап, тап, свайп, тап, тап, тап (сценарий «после свайпа тач умирает», STATE п.152)."""
import fcntl, os, struct, sys, time

UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT, UI_SET_PROPBIT = 0x40045564, 0x40045565, 0x40045567, 0x4004556E
UI_DEV_SETUP, UI_ABS_SETUP, UI_DEV_CREATE, UI_DEV_DESTROY = 0x405C5503, 0x401C5504, 0x5501, 0x5502
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
BTN_TOUCH, ABS_X, ABS_Y, ABS_MT_SLOT, ABS_MT_X, ABS_MT_Y, ABS_MT_ID = 0x14A, 0, 1, 0x2F, 0x35, 0x36, 0x39
MAXV = 1000

fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
def ev(t, c, v): os.write(fd, struct.pack("llHHi", 0, 0, t, c, v))
def syn(): ev(EV_SYN, 0, 0)

for t in (EV_KEY, EV_ABS): fcntl.ioctl(fd, UI_SET_EVBIT, t)
fcntl.ioctl(fd, UI_SET_KEYBIT, BTN_TOUCH)
fcntl.ioctl(fd, UI_SET_PROPBIT, 1)  # INPUT_PROP_DIRECT: сенсорный экран, не тачпад
for code in (ABS_X, ABS_Y, ABS_MT_SLOT, ABS_MT_X, ABS_MT_Y, ABS_MT_ID):
    fcntl.ioctl(fd, UI_SET_ABSBIT, code)
    mx = 9 if code == ABS_MT_SLOT else 65535 if code == ABS_MT_ID else MAXV
    fcntl.ioctl(fd, UI_ABS_SETUP, struct.pack("<H2x6i", code, 0, 0, mx, 0, 0, 0))
fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack("<HHHH80sI", 3, 0x1234, 0x5678, 1, b"fake-touch", 0))
fcntl.ioctl(fd, UI_DEV_CREATE)
time.sleep(1.5)  # sway подхватывает устройство

tid = [100]
def down(x, y):
    tid[0] += 1
    ev(EV_ABS, ABS_MT_SLOT, 0); ev(EV_ABS, ABS_MT_ID, tid[0]); ev(EV_ABS, ABS_MT_X, x); ev(EV_ABS, ABS_MT_Y, y)
    ev(EV_ABS, ABS_X, x); ev(EV_ABS, ABS_Y, y); ev(EV_KEY, BTN_TOUCH, 1); syn()
def move(x, y):
    ev(EV_ABS, ABS_MT_X, x); ev(EV_ABS, ABS_MT_Y, y); ev(EV_ABS, ABS_X, x); ev(EV_ABS, ABS_Y, y); syn()
def up():
    ev(EV_ABS, ABS_MT_ID, -1); ev(EV_KEY, BTN_TOUCH, 0); syn()
def tap(x, y): down(x, y); time.sleep(0.1); up(); time.sleep(0.35)
def swipe(x1, y1, x2, y2, ms=300, n=15):
    down(x1, y1)
    for i in range(1, n + 1):
        time.sleep(ms / 1000 / n); move(x1 + (x2 - x1) * i // n, y1 + (y2 - y1) * i // n)
    up(); time.sleep(0.5)

a = sys.argv[1:] or ["seq"]
try:
    if a[0] == "tap": tap(int(a[1]), int(a[2]))
    elif a[0] == "swipe": swipe(*map(int, a[1:5]), *(int(a[5]),) if len(a) > 5 else ())
    elif a[0] == "probe":  # варианты свайпа; после каждого — тап; счётчики по TAPLOG (a[1])
        def cnt():
            try: return [l.split()[1] for l in open(a[1])]
            except OSError: return []
        for ms, n, dy in ((120, 8, 150), (250, 30, 300), (400, 40, 500), (150, 10, 600), (800, 60, 500)):
            c0 = cnt(); swipe(500, 800, 500, 800 - dy, ms, n); c1 = cnt()[len(c0):]
            tap(500, 500); c2 = cnt()[len(c0) + len(c1):]
            print("свайп %dмс/%d шагов/dy=%d: события %s | тап после: %s" % (
                ms, n, dy, sorted(set(c1)) or "нет", "доставлен" if "MouseDown" in c2 else "НЕ ДОСТАВЛЕН"))
    elif a[0] == "seq":
        for _ in range(2): tap(500, 500)
        swipe(500, 700, 500, 400)
        for _ in range(3): tap(500, 500)
finally:
    time.sleep(0.3); fcntl.ioctl(fd, UI_DEV_DESTROY); os.close(fd)
