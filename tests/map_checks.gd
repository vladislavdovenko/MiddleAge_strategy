extends SceneTree

const Valley = preload("res://map/valley.gd")
var failed := 0
func check(b: bool, description: String) -> void:
	if not b:
		failed += 1
		printerr("FAIL: ", description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var ui = load("res://main.tscn").instantiate()
	root.add_child(ui)
	ui.set_process(false)
	await process_frame
	var v: Valley = ui.valley
	var a := Vector2(110,265)
	var b := Vector2(850,265)
	var road := v.route(a,b,2)
	check(not road.is_empty() and is_equal_approx(road.times[-1],370.0),"road speed across open bridge")
	var field := v.route(Vector2(100,375), Vector2(154,375),2)
	check(not field.is_empty() and is_equal_approx(field.times[-1],54.0/1.1),"field speed")
	var curved := v.route(Vector2(480,100),Vector2(640,452),2)
	check(curved.is_empty(),"water destination rejected")
	curved = v.route(Vector2(380,140),Vector2(640,452),2)
	check(not curved.is_empty(),"opposite-bank field reachable")
	for i in range(1,curved.points.size()):
		for k in 21:
			check(v.walkable(curved.points[i-1].lerp(curved.points[i],k/20.0)),"route stays on land or deck")
	v.bridge_open = false
	check(v.route(a,b,2).is_empty(),"closed crossing")
	check(not v.route(a,Vector2(240,380),2).is_empty(),"same bank still reachable")
	v.bridge_open = true
	ui.order(b)
	var previous = ui.group
	ui.world.advance(220)
	check(ui.group == previous and v.region_at(ui.group.position)=="Східний берег","same group crosses regional boundary")
	ui._refresh()
	var pos: Vector2 = ui.group.position
	var clock: int = ui.world.time_seconds
	for i in 20: ui.set_zoom(i%2==0,pos)
	check(ui.group.position==pos and ui.world.time_seconds==clock,"zoom preserves state")
	ui.get_node("Bar/Pause").pressed.emit()
	ui._process(9)
	check(ui.world.time_seconds==clock,"paused clock")
	ui.get_node("Bar/Pause").pressed.emit()
	ui._bridge()
	check(not v.bridge_open,"toggle closure")
	ui.order(a)
	check("недоступна" in ui.notice,"unreachable click gives feedback")
	ui._bridge()
	ui.order(a)
	ui._bridge()
	check(not ui.group.moving,"closure stops outstanding cross-bank order")
	ui._bridge()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var dest := Vector2(700,300)
	event.position = ui.get_node("Frame/View").get_canvas_transform()*dest
	ui.get_node("Frame").gui_input.emit(event)
	check(ui.group.target.distance_to(dest)<0.01 and ui.group.moving,"map click issues world-space order")
	ui.world.advance(6500-ui.world.time_seconds)
	ui._refresh()
	check("07:48:20" in ui.get_node("Bar/Clock").text,"clock at 6500 seconds")
	if "--preview" in OS.get_cmdline_user_args():
		ui.group.position = Vector2(270,265)
		ui.order(b)
		ui.set_zoom(true,Vector2(350,260))
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		check(frame.save_png("res://map-preview.png")==OK,"save rendered preview")
	print("Map checks: ",failed," failed")
	quit(1 if failed else 0)
