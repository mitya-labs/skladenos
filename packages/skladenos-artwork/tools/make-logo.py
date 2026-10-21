#!/usr/bin/env python3
# Генератор логотипа skladenOS (SVG): знак «гармошка» (Z-сложение), подпись «skladenOS» кривыми из JetBrains Mono Bold.
#   python3 make-logo.py --font JetBrainsMono-Bold.ttf --out ../files/usr/share/skladenos/logo
# Нужен fonttools (pip install fonttools). Растровые иконки (PNG) из icon.svg делает tools/make-icons.sh.
# © 2026 Dmitrii Trifonov. All rights reserved (логотип — отличительный знак проекта, см. assets/NOTICE.md).
# Шрифт JetBrains Mono — SIL OFL 1.1: контуры букв в логотипе допустимы.
import argparse, os
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

# Знак: четыре грани гармошки на сетке 320×160 (грань 80 px, сдвиг сгиба 30 px)
MARK = [  # (точки, роль цвета)
    ("0,30 80,0 80,130 0,160", "light"),
    ("80,0 160,30 160,160 80,130", "dark"),
    ("160,30 240,0 240,130 160,160", "light"),
    ("240,0 320,30 320,160 240,130", "mid"),
]
PALETTE = {
    "dark": {"light": "#FFE55C", "dark": "#B89B33", "mid": "#E0C247", "text": "#E8E9EF", "accent": "#FFE55C", "bg": "#0D0E15"},    # для тёмного фона
    "light": {"light": "#F5B800", "dark": "#B8860B", "mid": "#D9A000", "text": "#14151C", "accent": "#C88F00", "bg": "#FFFFFF"},   # для светлого фона
}


def mark_svg(pal, x=0, y=0, scale=1.0):
    g = "".join('<polygon points="%s" fill="%s"/>' % (pts, pal[role]) for pts, role in MARK)
    return '<g transform="translate(%s %s) scale(%s)">%s</g>' % (x, y, scale, g)


class Font:
    def __init__(self, path):
        self.f = TTFont(path); self.gs = self.f.getGlyphSet(); self.cmap = self.f.getBestCmap()
        self.upm = self.f["head"].unitsPerEm; self.cap = self.f["OS/2"].sCapHeight

    def text(self, s, x, baseline, size):
        k = size / self.upm; d = []; adv = 0
        for ch in s:
            name = self.cmap[ord(ch)]; pen = SVGPathPen(self.gs)
            self.gs[name].draw(TransformPen(pen, (k, 0, 0, -k, x + adv, baseline)))
            d.append(pen.getCommands()); adv += self.gs[name].width * k
        return " ".join(d), adv


def svg(w, h, body, bg=None):
    r = '<rect width="%s" height="%s" fill="%s"/>' % (w, h, bg) if bg else ""
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" width="%s" height="%s">'
            '<title>skladenOS</title>%s%s</svg>\n' % (w, h, w, h, r, body))


def wordmark(font, pal, x, baseline, size):
    d1, a1 = font.text("sklad" "en", x, baseline, size)
    d2, a2 = font.text("OS", x + a1, baseline, size)
    return '<path d="%s" fill="%s"/><path d="%s" fill="%s"/>' % (d1, pal["text"], d2, pal["accent"]), a1 + a2


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--font", required=True); ap.add_argument("--out", required=True)
    a = ap.parse_args(); os.makedirs(a.out, exist_ok=True); font = Font(a.font)
    pad = 32
    for theme, pal in PALETTE.items():
        # знак
        open(f"{a.out}/logo-mark-{theme}.svg", "w").write(svg(320 + 2 * pad, 160 + 2 * pad, mark_svg(pal, pad, pad)))
        # горизонтальный: знак слева, подпись справа по центру знака
        size = 96; capH = font.cap * size / font.upm; gap = 48
        body, tw = wordmark(font, pal, pad + 320 + gap, pad + 80 + capH / 2, size)
        open(f"{a.out}/logo-horizontal-{theme}.svg", "w").write(svg(round(2 * pad + 320 + gap + tw), 160 + 2 * pad, mark_svg(pal, pad, pad) + body))
        # вертикальный: знак над подписью, по центру
        size = 110; capH = font.cap * size / font.upm; gap = 56
        _, tw = wordmark(font, pal, 0, 0, size); W = round(max(320, tw) + 2 * pad)
        body, _ = wordmark(font, pal, (W - tw) / 2, pad + 160 + gap + capH, size)
        open(f"{a.out}/logo-stacked-{theme}.svg", "w").write(svg(W, round(2 * pad + 160 + gap + capH), mark_svg(pal, (W - 320) / 2, pad) + body))
    # иконка приложения: знак на тёмной скруглённой плитке
    pal = PALETTE["dark"]; S = 512; ms = 0.72; mw = 320 * ms; mh = 160 * ms
    icon = ('<rect width="%d" height="%d" rx="112" fill="%s"/>' % (S, S, pal["bg"]) + mark_svg(pal, (S - mw) / 2, (S - mh) / 2, ms))
    open(f"{a.out}/icon.svg", "w").write(svg(S, S, icon))
    print("ok:", sorted(os.listdir(a.out)))


if __name__ == "__main__":
    main()
