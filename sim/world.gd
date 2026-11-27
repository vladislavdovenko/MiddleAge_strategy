extends RefCounted

enum Phase { MORNING, DAY, EVENING, NIGHT }
const PHASE_SECONDS := 6 * 3600

class Group:
	var position: Vector2
	var origin: Vector2
	var target: Vector2
	var speed_mps: float
	var departed_at: int
	var due_at: int
	var order: int
	var moving := false

var time_seconds := 0
var groups := {}
var arrivals: Array[Dictionary] = []
var _next_order := 0

func phase() -> Phase:
	return (int(time_seconds / PHASE_SECONDS) % 4) as Phase

func add_group(id: String, position: Vector2, speed_mps: float) -> bool:
	if id.is_empty() or groups.has(id) or not position.is_finite() or not is_finite(speed_mps) or speed_mps <= 0:
		return false
	var group := Group.new()
	group.position = position
	group.speed_mps = speed_mps
	groups[id] = group
	return true

func move_group(id: String, target: Vector2) -> bool:
	if not groups.has(id) or not target.is_finite():
		return false
	var group: Group = groups[id]
	group.origin = group.position
	group.target = target
	group.departed_at = time_seconds
	group.due_at = time_seconds + ceili(group.origin.distance_to(target) / group.speed_mps)
	group.order = _next_order
	_next_order += 1
	group.moving = true
	if group.due_at == time_seconds:
		advance(0)
	return true

func advance(seconds: int) -> void:
	if seconds < 0:
		push_error("Model time cannot run backwards")
		return
	time_seconds += seconds
	var due: Array[Dictionary] = []
	for id in groups:
		var group: Group = groups[id]
		if not group.moving:
			continue
		if group.due_at <= time_seconds:
			group.position = group.target
			group.moving = false
			due.append({"id": id, "time": group.due_at, "order": group.order})
		else:
			var distance := group.speed_mps * (time_seconds - group.departed_at)
			group.position = group.origin.move_toward(group.target, distance)
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.time < b.time or (a.time == b.time and a.order < b.order))
	arrivals.append_array(due)
