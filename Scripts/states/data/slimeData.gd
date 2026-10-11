class_name SlimeData
extends Resource

# ============================================
# ОСНОВНАЯ ИНФОРМАЦИЯ
# ============================================
@export var id: String = "green"
@export var display_name: String = "Зелёный"
@export var description: String = "Обычный слизень. Медленный, но стабильный."
@export var sheet_texture: Texture2D
@export var shop_texture: Texture2D

# ============================================
# ЦЕНА (для магазина)
# ============================================
# Цены экспоненциальные: каждая следующая копия дороже предыдущей.
# Пока цена копии была фиксированной, одна удачная капля покупала
# весь магазин и прогресс заканчивался за пару минут.
@export_group("Цена")
@export var unlock_price: float = 0.0      # цена первого открытия (0 = стартовый)
@export var price: float = 20.0            # база для копий
@export var price_growth: float = 1.55     # множитель за каждую купленную копию

# ============================================
# УРОВНИ
# ============================================
# Уровень свой у каждого экземпляра: прокачивается конкретный слизень,
# а не весь вид. Цена уровня тоже экспоненциальная — при линейной
# уровни пролетались за минуты.
@export_group("Уровни")
@export var level_price: float = 30.0      # цена перехода 1 → 2
@export var level_growth: float = 1.70     # множитель за каждый уровень
@export var max_level: int = 15
@export var level_drop_bonus: float = 0.5  # +50% к капле за уровень

# Сколько таких слизней у игрока сразу, без покупок. Иначе новая игра
# начинается с нуля денег и без слизней — до первой капли негде заработать.
@export var starter_count: int = 1

# ============================================
# ДВИЖЕНИЕ
# ============================================
@export_group("Движение")
@export var speed: float = 150.0
@export var min_move_time: float = 2.0
@export var max_move_time: float = 5.0
@export var min_idle_time: float = 1.0
@export var max_idle_time: float = 3.0

# ============================================
# КАПЛИ (доход)
# ============================================
@export_group("Капли")
@export var drop_texture: Texture2D
@export var drop_color: Color = Color(0.3, 1.0, 0.4, 1.0)
@export var drop_value: float = 1.0
@export var min_drop_interval: float = 2.0
@export var max_drop_interval: float = 5.0

# ============================================
# ТРЕЙЛ (визуал)
# ============================================
@export_group("Трейл")
@export var trail_gradient: Texture2D

# ============================================
# ГОНКА
# ============================================
@export_group("Гонка")
@export var race_speed: int = 10
@export var race_stamina: int = 10
@export var race_grip: int = 10
@export var race_weight: int = 10
@export var race_luck: int = 5

# Прибавка к гонковым статам за каждый уровень экземпляра. Без этого
# прокачка работала ровно на одну цифру — стоимость капли, — и гонка
# никак не зависела от того, что наделано на ферме.
@export var race_stat_per_level: float = 1.0

# Гонковые статы адресуются по имени, поэтому заранее очерчиваем
# список: get_race_stat по чужому имени вернул бы null вместо числа
const RACE_STATS := ["race_speed", "race_stamina", "race_grip",
	"race_weight", "race_luck"]

# ============================================
# УТИЛИТЫ
# ============================================
func is_starter() -> bool:
	return starter_count > 0

## Цена следующей копии вида. owned — сколько таких уже куплено.
## Гарантируем, что цена не падает: первая копия открывает вид и
## может стоить дороже базовой, и без проверки вторая выходила бы
## дешевле первой (300 → 176 у синего).
func get_copy_price(owned: int) -> float:
	if owned <= 0:
		return unlock_price
	return maxf(price * pow(price_growth, owned), get_copy_price(owned - 1))

## Цена перехода с текущего уровня на следующий
func get_level_price(level: int) -> float:
	if level >= max_level:
		return 0.0
	return level_price * pow(level_growth, maxi(level, 1) - 1)

## Сколько стоит капля этого слизня на данном уровне
func get_drop_value(level: int) -> float:
	return drop_value * (1.0 + (maxi(level, 1) - 1) * level_drop_bonus)

## Гонковый стат вида на уровне экземпляра. stat — имя из RACE_STATS
func get_race_stat(stat: String, level: int) -> float:
	if not RACE_STATS.has(stat):
		return 0.0
	return float(get(stat)) + float(maxi(level, 1) - 1) * race_stat_per_level

func get_effective_price(is_unlocked: bool) -> float:
	return price if is_unlocked else unlock_price
