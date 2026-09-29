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
@export_group("Цена")
@export var unlock_price: float = 0.0      # цена первого открытия (0 = стартовый)
@export var price: float = 50.0            # цена за каждую следующую копию

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

# ============================================
# УТИЛИТЫ
# ============================================
func is_starter() -> bool:
	return unlock_price <= 0.0

func get_effective_price(is_unlocked: bool) -> float:
	return price if is_unlocked else unlock_price
