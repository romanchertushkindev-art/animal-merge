"""Симуляция экономики AnimalMerge.

Модель дохода: каждый слизень на ферме роняет каплю раз в
avg(min_drop_interval, max_drop_interval) со значением
drop_value * (1 + (level - 1) * level_drop_bonus).

Игрок в активной игре собирает всё кликом (100%), поэтому потолок
дохода = сумма потоков слизней. Жаба добавляет ~40% пассивно с тех
слизей, что оказались в её радиусе — это бонус за игру офлайн, в
модели активной игры его не считаем.

Стратегия покупки: жадная — берём то, что быстрее окупается.
"""


class Slime:
    def __init__(self, sid, data):
        self.sid = sid
        self.d = data

    def drop_rate(self):
        return 1.0 / ((self.d["drop_min"] + self.d["drop_max"]) / 2.0)

    def value(self, level):
        return self.d["drop_value"] * (1.0 + (level - 1) * self.d["level_bonus"])

    def income(self, level):
        return self.drop_rate() * self.value(level)


SLIMES = {
    "green": dict(
        name="Зелёный", unlock=100.0, price=200.0, price_growth=1.55,
        drop_value=10.0, drop_min=2.0, drop_max=5.0,
        level_price=300.0, level_growth=1.70, max_level=15, level_bonus=0.5,
    ),
    "blue": dict(
        name="Синий", unlock=3000.0, price=2000.0, price_growth=1.6,
        drop_value=40.0, drop_min=1.0, drop_max=3.0,
        level_price=1700.0, level_growth=1.70, max_level=15, level_bonus=0.5,
    ),
}

# Жаба покупается один раз: max_count = 1.
# FROG_COVERAGE — доля потока капель, которую жаба успевает съесть.
# Измерено в игре: 5 слизней 1-го уровня дают поток 65.7/с, жаба
# приносит 6.9/с при выплате 40% → съедает ~26% потока.
FROG = dict(name="Жаба", unlock=3000.0, price=3000.0, price_growth=1.7,
            max_count=1, coverage=0.26)

SLOTS = 5

# Гонка. Пока идёт забег, ферма не тикает: это отдельная сцена,
# капли с неё не падают. Значит забег — не «плюс к доходу», а замена.
#
# Выплата ПРОПОРЦИОННА доходу ферма: reward = доход × RACE_DURATION × 1.5.
# Фиксированная сумма здесь невозможна — 3600 слизи это огромные деньги
# на пятой минуте (синий открывался на 4-й вместо 21-й) и ничто на
# третьем часе, а доход растёт в сотни раз. Привязка к доходу держит
# гонку на одной и той же выгоде на любом этапе.
RACE_PERIOD = 600.0
RACE_DURATION = 56.0
RACE_MULTIPLIER = 1.2

RACE_VARIANTS = [
    ("без гонки", None),
    ("5м ×1.5", (300.0, 1.5)),
    ("10м ×1.2", (600.0, 1.2)),
    ("10м ×1.5", (600.0, 1.5)),
    ("15м ×1.5", (900.0, 1.5)),
    ("10м ×2.0", (600.0, 2.0)),
]


def copy_cost(sid, owned):
    d = SLIMES[sid]
    if owned <= 0:
        return d["unlock"]
    # как в SlimeData.get_copy_price: цена не падает на второй копии
    return max(d["price"] * d["price_growth"] ** owned,
               d["unlock"] if owned == 1 else copy_cost(sid, owned - 1))


def level_cost(sid, level):
    """Цена перехода с level на level+1."""
    d = SLIMES[sid]
    return d["level_price"] * d["level_growth"] ** (level - 1)


def simulate(seconds, strategy="greedy", dt=0.5, verbose=False):
    money = 0.0
    t = 0.0
    race_cooldown = RACE_PERIOD
    race_remaining = 0.0

    # owned[sid] — сколько всего куплено, on_scene[sid] — сколько стоит на ферме
    owned = {s: 0 for s in SLIMES}
    on_scene = {s: 0 for s in SLIMES}
    levels = []  # список (sid, level) — по экземплярам
    # Жабы покупаются: она одна на ферме (max_count = 1)
    frogs = 0

    # Стартовый слизень
    levels.append(("green", 1))
    on_scene["green"] = 1
    owned["green"] = 1

    milestones = []
    logged = set()

    def income():
        total = 0.0
        for s, l in levels:
            d = SLIMES[s]
            rate = 1.0 / ((d["drop_min"] + d["drop_max"]) / 2.0)
            total += rate * d["drop_value"] * (1.0 + (l - 1) * d["level_bonus"])
        # жаба добавляет долю потока, но платит за него 40%
        if frogs > 0:
            total += total * FROG["coverage"] * 0.4
        return total

    while t < seconds:
        # --- гонка: раз в RACE_PERIOD занимает первые RACE_DURATION
        #     секунд цикла, в это время ферма молчит, на финише платят
        if race_cooldown <= 0.0:
            race_remaining = RACE_DURATION
            race_cooldown = RACE_PERIOD
        race_cooldown -= dt
        in_race = race_remaining > 0.0
        if in_race:
            race_remaining -= dt
            if race_remaining <= 0.0:
                money += income() * RACE_DURATION * RACE_MULTIPLIER
        else:
            # --- доход с фермы
            money += income() * dt

        # --- покупки (траты мгновенные, но ограничены деньгами и слотами)
        bought = True
        guard = 0
        while bought and guard < 20:
            bought = False
            guard += 1
            cands = []

            # копии — только если есть свободный слот. Покупать «в запас»
            # при экспоненциальной цене бессмысленно: счётчик owned растёт,
            # цена следующей копии взлетает, а слизень так и не работает
            for sid, d in SLIMES.items():
                if on_scene[sid] >= SLOTS:
                    continue
                c = copy_cost(sid, owned[sid])
                if c > money:
                    continue
                delta = d["drop_value"] / ((d["drop_min"] + d["drop_max"]) / 2.0)
                cands.append((c / max(delta, 1e-9), "copy", sid, c))

            # уровни
            for i, (sid, lvl) in enumerate(levels):
                if lvl >= SLIMES[sid]["max_level"]:
                    continue
                c = level_cost(sid, lvl)
                if c > money:
                    continue
                d = SLIMES[sid]
                gain = d["drop_value"] * d["level_bonus"] / (
                    (d["drop_min"] + d["drop_max"]) / 2.0)
                cands.append((c / max(gain, 1e-9), "level", (i, lvl), c))

            # жаба: доход = доля потока × выплата
            if frogs < FROG["max_count"]:
                c = FROG["unlock"] if frogs == 0 else FROG["price"] * FROG["price_growth"] ** frogs
                gain = income() * FROG["coverage"] * 0.4
                if c <= money and gain > 0.0:
                    cands.append((c / gain, "frog", None, c))

            if not cands:
                break
            cands.sort(key=lambda x: x[0])
            _, kind, key, c = cands[0]
            if c > money:
                break

            money -= c
            bought = True

            if kind == "copy":
                owned[key] += 1
                on_scene[key] += 1
                levels.append((key, 1))
            elif kind == "level":
                i, lvl = key
                levels[i] = (levels[i][0], lvl + 1)
            elif kind == "frog":
                frogs += 1

        # --- вехи
        checks = [
            ("Первый уровень 5", any(l >= 5 for _, l in levels)),
            ("Синий открыт", owned["blue"] > 0),
            ("Все 5 слотов", sum(on_scene.values()) >= SLOTS),
            ("Жаба куплена", frogs > 0),
            ("Первый ур.10", any(l >= 10 for _, l in levels)),
            ("Первый ур.15", any(l >= 15 for _, l in levels)),
            ("Все ур.15", all(l >= 15 for _, l in levels)),
        ]
        for name, ok in checks:
            if ok and name not in logged:
                logged.add(name)
                milestones.append((name, t, money, income()))

        t += dt

    return milestones, money, income(), levels, owned, on_scene, frogs


def fmt(sec):
    m = int(sec // 60)
    s = int(sec % 60)
    h = m // 60
    if h:
        return "%dч %02dм" % (h, m % 60)
    if m:
        return "%dм %02dс" % (m, s)
    return "%dс" % s


import copy

# Эталонные значения: apply() всегда откатывается к ним, иначе
# варианты протекают друг в друга и результаты бессмысленны.
PRISTINE_SLIMES = copy.deepcopy(SLIMES)
PRISTINE_FROG = copy.deepcopy(FROG)


def apply(cfg):
    """Забирает числовые настройки из словаря в константы выше."""
    SLIMES.clear()
    SLIMES.update(copy.deepcopy(PRISTINE_SLIMES))
    FROG.clear()
    FROG.update(copy.deepcopy(PRISTINE_FROG))
    for sid, patch in cfg.get("slimes", {}).items():
        SLIMES[sid].update(patch)
    for k in ("unlock", "price", "price_growth", "max_count"):
        if k in cfg.get("frog", {}):
            FROG[k] = cfg["frog"][k]


def milestone_row(ms, names):
    out = {}
    for name, t, m, i in ms:
        out[name] = t
    return [out.get(n) for n in names]


MS_NAMES = ["Первый уровень 5", "Синий открыт", "Все 5 слотов", "Жаба куплена",
            "Первый ур.10", "Первый ур.15", "Все ур.15"]


def fmt_opt(t):
    return fmt(t) if t is not None else "—"


BASE = {
    "slimes": {},
    "frog": {},
}

VARIANTS = [
    ("итоговый", {}),
    ("уровни жёстче", {"slimes": {"green": dict(level_price=400.0, level_growth=1.75),
                                  "blue": dict(level_price=2200.0, level_growth=1.75)}}),
    ("копии жёстче", {"slimes": {"green": dict(price=280.0, price_growth=1.62),
                                 "blue": dict(price=2800.0, price_growth=1.68)}}),
    ("мягче", {"slimes": {"green": dict(level_price=240.0, level_growth=1.62),
                          "blue": dict(level_price=1350.0, level_growth=1.62)}}),
]

def merge(base, patch):
    out = {"slimes": {}, "frog": {}}
    for sid in set(base.get("slimes", {})) | set(patch.get("slimes", {})):
        merged = dict(base.get("slimes", {}).get(sid, {}))
        merged.update(patch.get("slimes", {}).get(sid, {}))
        out["slimes"][sid] = merged
    out["frog"] = dict(base.get("frog", {}), **patch.get("frog", {}))
    return out


if __name__ == "__main__":
    HORIZON = 24 * 3600

    # Сначала подбор награды за гонку при базовых числах вида
    print("=== Награда за гонку ===")
    print("%-14s %s" % ("гонка", "  ".join("%11s" % n[:11] for n in MS_NAMES)))
    print("-" * 100)
    base_period, base_mult = RACE_PERIOD, RACE_MULTIPLIER
    for title, params in RACE_VARIANTS:
        if params:
            RACE_PERIOD, RACE_MULTIPLIER = params
        else:
            RACE_PERIOD = 1e12      # гонки нет
        apply(BASE)
        ms, _, _, _, _, _, _ = simulate(HORIZON)
        print("%-14s %s" % (title, "  ".join("%11s" % fmt_opt(t)
                                            for t in milestone_row(ms, MS_NAMES))))
    RACE_PERIOD, RACE_MULTIPLIER = base_period, base_mult
    print()

    # Затем варианты баланса вида
    print("=== Баланс вида ===")
    print("%-18s %s" % ("вариант", "  ".join("%11s" % n[:11] for n in MS_NAMES)))
    print("-" * 100)
    for title, patch in VARIANTS:
        apply(merge(BASE, patch))
        ms, money, inc, levels, owned, on_scene, frogs = simulate(HORIZON)
        row = milestone_row(ms, MS_NAMES)
        print("%-18s %s" % (title, "  ".join("%11s" % fmt_opt(t) for t in row)))

    # Подробный разбор выбранного кандидата
    print()
    apply(merge(BASE, VARIANTS[-1][1]))
    ms, money, inc, levels, owned, on_scene, frogs = simulate(HORIZON)
    print("=== Подробно: %s ===" % VARIANTS[-1][0])
    for name, t, m, i in sorted(ms, key=lambda x: x[1]):
        print("  %-16s %9s   (деньги %10.0f, доход %8.2f/с)" % (name, fmt(t), m, i))
    print("  через %s: на ферме %s, жаб %d, доход %.2f/с, накоплено %.0f"
          % (fmt(HORIZON), {k: v for k, v in on_scene.items() if v}, frogs, inc, money))