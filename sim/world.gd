extends RefCounted

enum Phase { MORNING, DAY, EVENING, NIGHT }
const PHASE_SECONDS := 6 * 3600

class Group:
	var position: Vector2
	var origin: Vector2
	var target: Vector2
	var speed_mps: float
	var path: PackedVector2Array
	var times: PackedFloat64Array
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
	var duration := group.position.distance_to(target) / group.speed_mps
	return follow_route(id, PackedVector2Array([group.position,target]), PackedFloat64Array([0,duration]))

func follow_route(id: String, points: PackedVector2Array, times: PackedFloat64Array) -> bool:
	if not groups.has(id) or points.is_empty() or points.size() != times.size(): return false
	var group: Group = groups[id]
	if not points[0].is_equal_approx(group.position) or times[0] != 0: return false
	for i in points.size():
		if not points[i].is_finite() or not is_finite(times[i]): return false
		if i > 0 and (times[i] < times[i-1] or (times[i] == times[i-1] and points[i] != points[i-1])): return false
	group.path = points.duplicate()
	group.times = times.duplicate()
	group.origin = group.position
	group.target = points[-1]
	group.departed_at = time_seconds
	group.due_at = time_seconds + ceili(times[-1])
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
			var elapsed := float(time_seconds - group.departed_at)
			var i := clampi(group.times.bsearch(elapsed, false), 1, group.path.size()-1)
			var fraction := (elapsed-group.times[i-1])/(group.times[i]-group.times[i-1])
			group.position = group.path[i-1].lerp(group.path[i],fraction)
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.time < b.time or (a.time == b.time and a.order < b.order))
	arrivals.append_array(due)
