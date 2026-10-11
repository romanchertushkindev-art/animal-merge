"""Генерация слоёв параллакса для гонки.

Слои кладутся в Sprites/race/ и намеренно сделаны простыми заготовками:
их потом можно перерисовать в aseprite, сохранив те же размеры и палитру.

    python Tools/generate_race_bg.py [путь к макету]

Если макет не передан, берётся дефолтный путь. Силуэт гор вытаскивается
из макета по верхнему краю тёмных пикселей; если макета нет — рисуется
процедурно с фиксированным seed, поэтому результат воспроизводим.
"""

import os
import random
import sys

from PIL import Image, ImageDraw

WS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(WS, "Sprites", "race")
DEFAULT_MOCKUP = os.path.expanduser(
    r"~\.dsh\attachments\v1\objects\09"
    r"\0919ecfe162d2fc5921188c7418a44a40f883b0e18949cfc74a14850d513d294"
)

# Палитра макета
SKY_TOP = (38, 34, 56)
SKY_MID = (74, 59, 92)
SKY_LOW = (101, 85, 97)      # #655561 — дымка макета
STAR = (216, 208, 232)

MOUNTAIN = (34, 32, 52)      # #222034
MOUNTAIN_FAR = (60, 54, 86)

GRASS = (106, 190, 48)       # #6ABE30
GRASS_STRIPE = (153, 229, 80)  # #99E550
GRASS_DARK = (90, 158, 42)
GRASS_LANE = (232, 245, 210)

OBSTACLE = (34, 32, 52)      # #222034 — тот же силуэт, что у гор
OBSTACLE_RIM = (62, 56, 96)  # светлая кромка сверху

VIEW_W, VIEW_H = 640, 360
SKY_H = 170                  # где начинается земля
MOUNTAIN_H = 124             # высота полосы гор
RIDGE_FLOOR = 0.32           # насколько низ может опуститься гряда (0..1)


def mockup_profile(path):
    """Верхний край тёмного силуэта по каждому столбцу макета.

    Возвращает профиль в координатах полосы гор (0 = вершина самой высокой
    горы) с уже закрытыми провалами: если в столбце тёмных пикселей нет,
    берём среднее соседей, иначе между пиками остаются дыры.
    """
    if not path or not os.path.isfile(path):
        return None
    im = Image.open(path).convert("RGB")
    w, h = im.size
    mountain = MOUNTAIN
    raw = []
    for x in range(w):
        top = None
        for y in range(h):
            if im.getpixel((x, y)) == mountain:
                top = y
                break
        raw.append(top)

    if all(t is None for t in raw):
        return None

    # Столбцы без гор ставим на уровень ближайших соседей с горой
    known = [i for i, t in enumerate(raw) if t is not None]
    for i, t in enumerate(raw):
        if t is None:
            left = max((j for j in known if j < i), default=None)
            right = min((j for j in known if j > i), default=None)
            if left is None:
                raw[i] = raw[right]
            elif right is None:
                raw[i] = raw[left]
            else:
                raw[i] = (raw[left] + raw[right]) // 2

    top_min = min(raw)
    return [t - top_min for t in raw]


def procedural_profile(width, seed, min_y, max_y, roughness):
    """Запасной силуэт, если макет недоступен."""
    rng = random.Random(seed)
    prof = []
    level = (min_y + max_y) // 2
    for x in range(width):
        if x % 7 == 0:
            level = rng.randint(min_y, max_y)
        prof.append(level)
        # лёгкий наклон, чтобы гребни не были ровными
        level = max(min_y, min(max_y, level + rng.randint(-roughness, roughness)))
    return prof


def make_silhouette(profile, width, height, color, bottom_solid=True):
    """Полоса гор: профиль слева + зеркальное отражение — шов ровно в центре."""
    src_w = len(profile)
    mirrored = list(reversed(profile))
    full = (profile + mirrored)[:width]
    while len(full) < width:            # на случай узкого макета
        full += list(reversed(full))

    top_min = min(full)
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for x, top in enumerate(full):
        y0 = max(0, top - top_min)
        draw.line([(x, y0), (x, height)], fill=color + (255,))
    if not bottom_solid:                # «дымка» внизу
        draw.rectangle([0, height - 3, width, height], fill=(0, 0, 0, 0))
    return img


def make_sky():
    """Вертикальный градиент в три ступени + редкие звёзды."""
    img = Image.new("RGB", (VIEW_W, VIEW_H), SKY_TOP)
    draw = ImageDraw.Draw(img)
    rng = random.Random(20240607)

    for y in range(SKY_H):
        t = y / max(1, SKY_H - 1)
        if t < 0.55:
            k = t / 0.55
            col = tuple(int(SKY_TOP[i] + (SKY_MID[i] - SKY_TOP[i]) * k) for i in range(3))
        else:
            k = (t - 0.55) / 0.45
            col = tuple(int(SKY_MID[i] + (SKY_LOW[i] - SKY_MID[i]) * k) for i in range(3))
        draw.line([(0, y), (VIEW_W, y)], fill=col)

    # Ниже линии горизонта небо всё равно перекрыто землёй, но если
    # текстура когда-то покажется целиком — не должно быть тёмной полосы
    draw.rectangle([0, SKY_H - 1, VIEW_W, VIEW_H], fill=SKY_LOW)

    for _ in range(90):
        x = rng.randrange(VIEW_W)
        y = rng.randrange(0, int(SKY_H * 0.6))
        if img.getpixel((x, y)) != SKY_TOP:   # только в верхней, тёмной части
            continue
        img.putpixel((x, y), STAR)
    return img


def make_ground():
    """Земля в полосу из макета: база + светлая полоса каждые 24 px."""
    ground_h = VIEW_H - SKY_H
    img = Image.new("RGB", (VIEW_W, ground_h), GRASS)
    draw = ImageDraw.Draw(img)
    rng = random.Random(777)

    for top in range(0, ground_h, 24):          # полосы как в макете
        draw.rectangle([0, top, VIEW_W, top + 3], fill=GRASS_STRIPE)

    # Редкие травинки, чтобы земля не была плоской заливкой
    for _ in range(150):
        x = rng.randrange(VIEW_W)
        y = rng.randrange(6, ground_h - 4)
        draw.line([(x, y), (x, y + 2)], fill=GRASS_DARK)
    return img


def add_rim(img, rim_color=OBSTACLE_RIM, thickness=2):
    """Светлая кромка по верхнему краю — как блик на силуэтах гор."""
    px = img.load()
    for x in range(img.width):
        for y in range(img.height):
            if px[x, y][3] == 0:
                continue
            if all(px[x, y - k][3] == 0 for k in range(1, thickness + 1)):
                px[x, y] = rim_color + (255,)
            break
    return img


def make_obstacle(kind, w, h):
    """Три препятствия разной высоты — чем выше, тем позже надо прыгать.

    Фигуры заданы в долях от размера, поэтому размер меняется одной строкой
    в main(), а пропорции не едут.
    """
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    def box(points):
        return [(x * w, y * h) for (x, y) in points]

    if kind == "rock":
        draw.polygon(box([(0.06, 1.0), (0.11, 0.45), (0.33, 0.07), (0.62, 0.0),
                          (0.85, 0.28), (0.95, 0.65), (0.95, 1.0)]),
                     fill=OBSTACLE + (255,))
    elif kind == "stump":
        draw.polygon(box([(0.18, 0.24), (0.82, 0.24), (0.82, 1.0), (0.18, 1.0)]),
                     fill=OBSTACLE + (255,))
        draw.polygon(box([(0.09, 0.14), (0.91, 0.14), (0.82, 0.28), (0.18, 0.28)]),
                     fill=OBSTACLE + (255,))
    else:  # crystal
        draw.polygon(box([(0.5, 0.0), (0.7, 0.37), (0.92, 1.0), (0.08, 1.0),
                          (0.3, 0.37)]), fill=OBSTACLE + (255,))

    return add_rim(img, thickness=3)


def main():
    mockup = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MOCKUP
    os.makedirs(OUT_DIR, exist_ok=True)

    profile = mockup_profile(mockup)
    if profile:
        # Профиль уже в координатах полосы гор; слишком высокие срезаем
        if max(profile) > MOUNTAIN_H:
            k = (MOUNTAIN_H - 8) / float(max(profile))
            profile = [int(v * k) for v in profile]
        # В профиле МАЛОЕ значение — это ВЫСОКАЯ гора, а большое — впадина.
        # Поэтому «пол» ставится сверху: впадины не должны проваливаться
        # в ноль, иначе при прокрутке участки выглядят пусто
        cap = MOUNTAIN_H - int((MOUNTAIN_H - 8) * RIDGE_FLOOR)
        profile = [min(v, cap) for v in profile]
        source = "макет %s" % os.path.basename(mockup)
    else:
        profile = procedural_profile(424, 99, 18, 54, 2)
        source = "процедурный профиль"
    print("силуэт гор:", source, "высота профиля", max(profile), "из", MOUNTAIN_H)

    sky = make_sky()
    sky.save(os.path.join(OUT_DIR, "bg_sky.png"))

    # Дальняя гряда: тот же профиль, приглушённый и ниже
    far = make_silhouette([int(v * 0.55) for v in profile], 640, MOUNTAIN_H, MOUNTAIN_FAR)
    far.save(os.path.join(OUT_DIR, "bg_mountains_far.png"))

    near = make_silhouette(profile, 848, MOUNTAIN_H, MOUNTAIN)
    near.save(os.path.join(OUT_DIR, "bg_mountains.png"))

    ground = make_ground()
    ground.save(os.path.join(OUT_DIR, "track_ground.png"))

    for kind, w, h in (("rock", 26, 20), ("stump", 30, 28), ("crystal", 26, 38)):
        make_obstacle(kind, w, h).save(
            os.path.join(OUT_DIR, "ob_%s.png" % kind))

    for name in sorted(os.listdir(OUT_DIR)):
        if name.endswith(".png"):
            p = os.path.join(OUT_DIR, name)
            print("  %-26s %s" % (name, Image.open(p).size))


if __name__ == "__main__":
    main()