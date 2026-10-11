"""Разбор макета гонки: снимаем палитру и пропорции, чтобы сгенерированные
слои параллакса были в его цветах. Запуск:

    python Tools/probe_mockup.py <путь к макету>
"""

import sys
from collections import Counter

from PIL import Image


def main(path: str) -> None:
    im = Image.open(path).convert("RGB")
    print("размер:", im.size)

    counter = Counter(im.getdata())
    print("топ-12 цветов макета:")
    for col, n in counter.most_common(12):
        print("   #%02X%02X%02X  rgb%s  %d px" % (col[0], col[1], col[2], col, n))

    w, h = im.size
    print("срез по центру (x=%d):" % (w // 2))
    prev = None
    for y in range(h):
        p = im.getpixel((w // 2, y))
        if p != prev:
            print("   y=%3d  #%02X%02X%02X" % (y, p[0], p[1], p[2]))
            prev = p


if __name__ == "__main__":
    main(sys.argv[1])