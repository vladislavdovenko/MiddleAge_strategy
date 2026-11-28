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
	v.set_gate("mill",false)
	var alternate := v.route(a,b,2)
	check(not alternate.is_empty() and alternate.times[-1]>road.times[-1],"southern crossing detour")
	v.set_gate("south",false)
	check(v.route(a,b,2).is_empty(),"closed crossing")
	check(not v.route(a,Vector2(240,380),2).is_empty(),"same bank still reachable")
	v.set_gate("mill",true)
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
	ui.campaign.toggle_gate("mill")
	check(not v.gates.mill,"toggle closure")
	ui.order(Vector2(810,380))
	check("недоступна" in ui.notice,"unreachable click gives feedback")
	ui.campaign.toggle_gate("mill")
	ui.order(a)
	ui.campaign.toggle_gate("mill")
	check(ui.group.moving,"unseen closure does not cancel a distant order")
	ui.group.position = Vector2(535,265)
	ui.campaign.reports["lord"]["south"] = false
	ui.campaign.update_routes()
	check(not ui.group.moving,"locally observed closure stops blocked order")
	ui.campaign.toggle_gate("mill")
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
	var campaign = ui.campaign
	var sight = campaign.sight
	var grass := Vector2(1500,710)
	check(sight.radius(grass,1)>sight.radius(grass,3),"night sight contracts")
	check(sight.radius(Vector2(245,150),1)<sight.radius(grass,1),"forest sight")
	check(sight.height(Vector2(820,825))>sight.height(grass) and sight.radius(Vector2(1070,380),1)>sight.radius(grass,1),"elevation improves range")
	check(sight.radius(Vector2(820,825),1)==sight.radius(Vector2(245,150),1),"forest cap also applies on hilltop")
	check(not sight.clear_line(Vector2(1030,380),Vector2(1110,380)),"crest blocks line between opposite slopes")
	var backups: Array = sight.obstacles.duplicate()
	sight.obstacles = [[grass+Vector2(15,0),5.0,12.0]]
	check(not sight.sees(grass,grass+Vector2(30,0),1),"object interrupts sight")
	sight.obstacles = backups
	var saved = campaign.snapshot()
	var lord = ui.world.groups["lord"]
	lord.position = v.crossings.mill.get_center()+Vector2(-15,0)
	campaign.observe()
	check(campaign.live.has("mill"),"bridge visible nearby")
	lord.position = grass
	campaign.observe()
	v.set_gate("mill",false)
	campaign.observe()
	check(not campaign.live.has("mill") and campaign.knowledge.mill.state,"bridge report remains stale")
	lord.position = v.crossings.mill.get_center()+Vector2(-15,0)
	campaign.observe()
	check(not campaign.knowledge.mill.state,"bridge state reacquired")
	check(campaign.restore(saved),"restore campaign")
	lord.position = Vector2(140,265)
	ui.world.groups["courier"].position = lord.position
	ui.world.groups["cart-01"].position = Vector2(270,265)
	campaign.observe()
	check(campaign.issue_cart(Vector2(375,265)) and not campaign.pending.is_empty(),"send messenger")
	campaign.advance(3)
	var travelling = campaign.snapshot()
	campaign.advance(120)
	var finish = campaign.snapshot()
	check(campaign.pending.is_empty() and ui.world.groups["cart-01"].position.distance_to(Vector2(375,265))<1,"order delivered")
	check(campaign.restore(travelling),"restore en route")
	campaign.advance(120)
	check(campaign.snapshot()==finish,"restored campaign follows same timeline")
	campaign.restore(saved)
	var editor = ui.get_node("Tools")
	ui.get_node("Bar/Editor").button_pressed = true
	var t_before: int = ui.world.time_seconds
	ui._process(20)
	check(ui.world.time_seconds==t_before,"clock paused while editing")
	editor.place.button_pressed = true
	editor.handle(event,Vector2(318,371))
	var new_tree: Sprite2D = editor.selected
	check(new_tree != null and new_tree.position == Vector2(318,371),"place object")
	var id: String = new_tree.get_meta("object_id")
	editor.scale_box.value = 73
	editor.layers.value = 10
	editor.mirror_h.button_pressed = true
	editor.mirror_v.button_pressed = true
	check(is_equal_approx(new_tree.scale.x,0.73) and new_tree.z_index==10 and new_tree.flip_h and new_tree.flip_v,"edit object properties")
	check(ui.objects.pick(new_tree.position+Vector2(0,-4))==new_tree or ui.objects.pick(new_tree.position+Vector2(0,-65))==new_tree,"object picking")
	var start_count: int = v.data.zones.size()
	editor.brush.select(1)
	editor.handle(event,Vector2(1440,620))
	editor.handle(event,Vector2(1480,665))
	check(v.data.zones.size()==start_count+1 and v.terrain_at(Vector2(1460,655))=="forest","paint terrain")
	var tmp := "user://editor-test-%s.json" % OS.get_process_id()
	check(ui.objects.save_layout(tmp)==OK and ui.objects.save_layout(tmp)==OK,"save and replace")
	var restored = ui.Objects.new()
	restored.setup(ui.valley.data,ui.valley.bounds,tmp)
	var loaded: Sprite2D = restored.sprites[id]
	check(loaded.position==new_tree.position and loaded.flip_h and loaded.flip_v and loaded.z_index==10 and loaded.scale==new_tree.scale,"reload exact placement")
	check(restored.map_data.zones.size()==start_count+1,"persist painted surface")
	editor.brush.select(editor.brush.item_count-1)
	editor.handle(event,Vector2(1460,655))
	check(v.data.zones.size()==start_count,"erase terrain")
	editor.brush.select(0)
	restored.free()
	DirAccess.remove_absolute(tmp)
	new_tree.flip_h = false
	new_tree.flip_v = false
	new_tree.z_index = 5
	ui.get_node("Bar/Editor").button_pressed = false
	check(v.factor_at(Vector2(245,150)) < v.data.field_factor,"forest slows movement")
	check(v.factor_at(Vector2(650,400)) < v.data.field_factor,"marsh slows movement")
	check(v.factor_at(Vector2(1150,390)) < v.factor_at(Vector2(1000,350)),"mountain forest overlap")
	for blocked in [Vector2(810,380),Vector2(300,480)]:
		check(not v.walkable(blocked),"blocked terrain")
	var detour := v.route(Vector2(760,390),Vector2(910,390),2)
	check(not detour.is_empty(),"route around marsh")
	for i in range(1,detour.points.size()):
		for j in 21: check(v.walkable(detour.points[i-1].lerp(detour.points[i],j/20.0)),"route avoids deep marsh")
	ui.set_zoom(false,Vector2(1810,960))
	check(ui.camera.position.x>1000 and ui.camera.position.y>650,"camera reaches far corner")
	# Compare against forced layers in an empty patch so unrelated foreground sprites
	# cannot change the reference image when the cart changes its layer.
	new_tree.position = Vector2(1450,670)
	ui.set_zoom(false,new_tree.position)
	if "--preview" in OS.get_cmdline_user_args():
		var old_time: int = ui.world.time_seconds
		var tones: Array[Color] = []
		for phase in 4:
			ui.world.time_seconds = phase*21600
			ui._refresh()
			var frame := await crop_at(ui,new_tree.position)
			tones.append(frame.get_pixel(3,3))
		for i in tones.size():
			for j in i: check(tones[i]!=tones[j],"four distinct rendered lighting filters")
		ui.world.time_seconds = old_time
		ui._refresh()
		for side in [-1,1]:
			ui.world.groups["lord"].position = new_tree.position+Vector2(-47,4)
			ui.world.groups["cart-01"].position = new_tree.position+Vector2(0,4*side)
			ui._refresh()
			await process_frame
			var natural := await crop_at(ui,new_tree.position)
			ui.cart.z_index = 5+side
			var expected := await crop_at(ui,new_tree.position)
			ui.cart.z_index = 5-side
			var reversed := await crop_at(ui,new_tree.position)
			check(natural.get_data()==expected.get_data() and natural.get_data()!=reversed.get_data(),"depth side=%d expected=%s distinct=%s" % [side,natural.get_data()==expected.get_data(),natural.get_data()!=reversed.get_data()])
			ui.cart.z_index = 5
		ui.get_node("Bar/Editor").button_pressed = true
		editor.choose(new_tree)
		ui.set_zoom(true,new_tree.position)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://map-preview.png")==OK,"editor screenshot")
	print("Map checks: ",failed," failed")
	quit(1 if failed else 0)

func crop_at(ui, pos: Vector2) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var view: SubViewport = ui.get_node("Frame/View")
	var center: Vector2 = view.get_canvas_transform()*pos
	return view.get_texture().get_image().get_region(Rect2i(Vector2i(center)-Vector2i(40,45),Vector2i(80,60)))
