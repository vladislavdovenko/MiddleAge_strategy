extends SceneTree

const World = preload("res://sim/world.gd")
const Types = preload("res://sim/unit_types.gd")
var failed := 0

func check(condition: bool, label: String) -> void:
	if not condition:
		failed += 1
		printerr("FAIL: ", label)

func fixture() -> World:
	var world := World.new()
	var speeds := Types.load_speeds()
	check(speeds.has("cart"), "cart template is available")
	world.add_group("a", Vector2.ZERO, speeds.get("cart", 0.0))
	world.move_group("a", Vector2(600, 0))
	return world

func _initialize() -> void:
	var world := fixture()
	world.advance(120)
	check(world.groups.a.position == Vector2(240, 0), "240 m at t=120")
	check(world.arrivals.is_empty(), "no early arrival")
	world.advance(179)
	check(world.groups.a.position == Vector2(598, 0), "moving at t=299")
	world.advance(1)
	check(world.groups.a.position == Vector2(600, 0), "destination at t=300")
	world.advance(100)
	check(world.arrivals == [{"id": "a", "time": 300, "order": 0}], "exactly one arrival")
	var small_steps := fixture()
	for step in 40:
		small_steps.advance(10)
	var large_step := fixture()
	large_step.advance(400)
	check(large_step.arrivals == small_steps.arrivals and small_steps.arrivals == world.arrivals, "partition independent events")
	check(large_step.groups.a.position == small_steps.groups.a.position, "partition independent position")

	world = World.new()
	for id in ["a", "b", "c"]:
		world.add_group(id, Vector2.ZERO, 2.0)
	world.move_group("c", Vector2(5, 0))
	world.move_group("b", Vector2(2, 0))
	world.move_group("a", Vector2(5, 0))
	world.advance(20)
	check(world.arrivals == [{"id":"b","time":1,"order":1},{"id":"c","time":3,"order":0},{"id":"a","time":3,"order":2}], "chronology, fractional seconds and stable ties")

	world = fixture()
	world.advance(100)
	world.move_group("a", Vector2(200, 20))
	world.advance(300)
	check(world.arrivals.size() == 1 and world.arrivals[0].time == 110, "redirect replaces pending arrival")
	world.move_group("a", Vector2(200, 20))
	check(world.arrivals.size() == 2 and world.arrivals[1].time == 400, "zero-length order arrives now")

	world = World.new()
	for phase_id in 4:
		check(world.phase() == phase_id, "phase at boundary")
		world.advance(21599)
		check(world.phase() == phase_id, "phase before boundary")
		world.advance(1)
	check(world.phase() == World.Phase.MORNING, "day rollover")
	if "--prove-failure" in OS.get_cmdline_user_args():
		check(false, "intentional runner self-test")
	print("Simulation checks: ", failed, " failed")
	quit(1 if failed else 0)
