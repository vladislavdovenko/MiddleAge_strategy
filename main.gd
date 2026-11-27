extends VBoxContainer

const World = preload("res://sim/world.gd")
const Types = preload("res://sim/unit_types.gd")
const PHASE_NAMES := ["Ранок", "День", "Вечір", "Ніч"]
var world := World.new()
var paused := false
var rate := 1
var remainder := 0.0

func _ready() -> void:
	$Actions/Pause.pressed.connect(_toggle_pause)
	$Actions/Speed.pressed.connect(_toggle_speed)
	$Actions/Reset.pressed.connect(_restart)
	_restart()

func _restart() -> void:
	world = World.new()
	var speeds := Types.load_speeds()
	if not speeds.has("cart"):
		$Status.text = "Помилка таблиці data/unit_types.tsv"
		set_process(false)
		get_tree().quit(1)
		return
	world.add_group("cart-01", Vector2.ZERO, speeds.cart)
	world.move_group("cart-01", Vector2(600, 0))
	paused = false
	rate = 1
	remainder = 0.0
	$Actions/Pause.text = "Пауза"
	$Actions/Speed.text = "Швидкість ×1"
	_refresh()

func _process(delta: float) -> void:
	if paused:
		return
	remainder += delta * rate
	var elapsed := floori(remainder)
	if elapsed > 0:
		remainder -= elapsed
		world.advance(elapsed)
		_refresh()

func _toggle_pause() -> void:
	paused = not paused
	$Actions/Pause.text = "Продовжити" if paused else "Пауза"

func _toggle_speed() -> void:
	rate = 60 if rate == 1 else 1
	$Actions/Speed.text = "Швидкість ×%d" % rate

func _refresh() -> void:
	var x: float = world.groups["cart-01"].position.x
	var state := "У дорозі" if world.arrivals.is_empty() else "Прибув · %d с" % world.arrivals[0].time
	$Status.text = "%s · %d с\n%.1f / 600 м · %s" % [PHASE_NAMES[world.phase()], world.time_seconds, x, state]
	$Distance.value = x
