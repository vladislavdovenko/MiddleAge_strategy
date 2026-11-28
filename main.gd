extends VBoxContainer

const World = preload("res://sim/world.gd")
const Types = preload("res://sim/unit_types.gd")
const Valley = preload("res://map/valley.gd")
const Terrain = preload("res://map/countryside.gd")
const PHASES := ["Ранок","День","Вечір","Ніч"]
const CART := "cart-01"
var world := World.new()
var valley := Valley.new()
var landscape := Terrain.new()
const Objects = preload("res://map/objects.gd")
var objects := Objects.new()
var cart := Sprite2D.new()
var wheel := ShaderMaterial.new()
var path := Line2D.new()
var terrain_changed := false
var selected := true
var marker := Polygon2D.new()
var remainder := 0.0
var paused := false
var rate_index := 1
var detail := false
var wheel_angle := 0.0
var notice := ""
var camera: Camera2D
var group: World.Group
var campaign := preload("res://sim/campaign.gd").new()
var fog := preload("res://map/fog.gd").new()
var tint := CanvasModulate.new()
var figures := {}
var sites := {}
var definitions := {}
var focus_id := "lord"
var action := "move"
var commands := HBoxContainer.new()
var last_fog := Vector2.INF
var last_phase := -1
const SAVE := "user://campaign-v1.save"

func command_button(label: String,callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	commands.add_child(button)

func focus_actor(id: String) -> void:
	focus_id = id
	group = world.groups[id]
	action = "move" if id==campaign.config.lord else "order"
	if campaign.live.has(id): set_zoom(detail,group.position)
	notice = "Клацніть місце призначення"
	_refresh()

func save_game() -> void:
	var file := FileAccess.open(SAVE+".tmp",FileAccess.WRITE)
	if file == null: return
	file.store_var(campaign.snapshot())
	file.flush()
	var err := file.get_error()
	file.close()
	if err==OK: err = DirAccess.rename_absolute(SAVE+".tmp",SAVE)
	notice = "Партію збережено" if err==OK else "Помилка запису партії"
	_refresh()

func load_game() -> void:
	var file := FileAccess.open(SAVE,FileAccess.READ)
	if file != null and campaign.restore(file.get_var()):
		last_fog = Vector2.INF
		remainder = 0
		notice = "Партію відновлено"
	else: notice = "Немає придатного збереження"
	_refresh()


func _ready() -> void:
	for button in $Bar.get_children():
		if button is Button:
			var panel := StyleBoxFlat.new()
			panel.bg_color = Color("#354338")
			panel.border_color = Color("#96845e")
			panel.set_border_width_all(1)
			panel.content_margin_left = 9
			panel.content_margin_right = 9
			button.add_theme_stylebox_override("normal", panel)
			button.add_theme_color_override("font_color", Color("#f3e8cd"))
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign.json"))
	campaign.setup(world,valley,config)
	group = world.groups[focus_id]
	camera = $Frame/View/Camera
	$Frame/View/Land.add_child(landscape)
	landscape.valley = valley
	$Frame/View/Land.add_child(objects)
	objects.setup(valley.data,valley.bounds)
	$Tools.setup(objects,valley.data.asset_labels)
	$Tools.surfaces_changed.connect(func():
		valley.graph = null
		terrain_changed = true
		landscape.queue_redraw()
		notice = "Місцевість змінено"
		_refresh())
	$Tools.feedback.connect(func(message: String): notice = message; _refresh())
	$Bar/Editor.toggled.connect(_edit_mode)
	cart.texture = load(valley.data.assets.cart)
	cart.offset.y = -cart.texture.get_height()*0.5
	cart.scale = Vector2.ONE*0.18
	cart.z_index = valley.data.cart_layer
	wheel.shader = preload("res://map/wheel.gdshader")
	cart.material = wheel
	objects.add_child(cart)
	figures[CART] = cart
	for spec in config.actors:
		definitions[spec.id] = spec
		if spec.id==CART: continue
		var s := Sprite2D.new()
		s.texture = load("res://art/%s.svg" % spec.asset)
		s.offset.y = -s.texture.get_height()/2.0
		s.scale = Vector2.ONE*float(spec.scale)
		s.z_index = cart.z_index
		objects.add_child(s)
		figures[spec.id] = s
	for site in config.sites:
		var s := Sprite2D.new()
		s.texture = load(valley.data.assets[site.asset])
		s.offset.y = -s.texture.get_height()/2.0
		s.position = campaign.locations[site.id]
		s.scale = Vector2.ONE*float(site.scale)
		s.z_index = cart.z_index
		objects.add_child(s)
		sites[site.id] = s
	fog.z_index = 12
	$Frame/View/Land.add_child(fog)
	$Frame/View/Land.add_child(tint)
	campaign.sight.rebuild_objects(objects.sprites)
	add_child(commands)
	move_child(commands,1)
	command_button("Феодал",func(): focus_actor("lord"))
	command_button("Наказ обозу",func(): focus_actor(CART))
	command_button("Зберегти партію",save_game)
	command_button("Відновити",load_game)
	command_button("Стан переправ",func():
		var parts := PackedStringArray()
		for id in valley.crossings:
			var entry: Dictionary = campaign.knowledge.get(id,{})
			var state := "невідомо"
			if not entry.is_empty():
				state = ("відкрита" if entry.state else "закрита")+(" (видно)" if campaign.live.has(id) else " (остання звістка)")
			parts.append(id+" · "+state)
		notice = " / ".join(parts)
		_refresh())

	path.width = 2.0
	path.default_color = Color("#8d4834c0")
	path.antialiased = true
	path.z_index = 0
	$Frame/View/Land.add_child(path)
	marker.color = Color("#883d2e")
	marker.polygon = PackedVector2Array([Vector2(0,-5),Vector2(4,0),Vector2(0,5),Vector2(-4,0)])
	marker.z_index = 0
	$Frame/View/Land.add_child(marker)
	$Bar/Pause.pressed.connect(_pause)
	$Bar/Speed.pressed.connect(_rate)
	$Bar/Bridge.pressed.connect(_bridge)
	$Bar/Zoom.pressed.connect(func(): set_zoom(not detail,group.position if campaign.live.has(focus_id) else camera.position))
	$Bar/Demo.text = "До переправи"
	$Bar/Demo.pressed.connect(func(): order(valley.crossings["mill"].get_center()))
	$Frame.gui_input.connect(_map_input)
	$Frame.resized.connect(_camera_bounds)
	set_zoom(false,group.position)
	_refresh()

	if not objects.read_error.is_empty():
		notice = objects.read_error
		_refresh()

func _edit_mode(active: bool) -> void:
	$Tools.visible = active
	$Tools.first_corner = Vector2.INF
	$Tools.occupied = world.groups["lord"].position
	$Tools.occupied_points.clear()
	for g in world.groups.values(): $Tools.occupied_points.append(g.position)
	commands.visible = not active
	campaign.sight.rebuild_objects(objects.sprites)
	last_fog = Vector2.INF
	if not active and terrain_changed:
		terrain_changed = false
		for id in world.groups:
			var g: World.Group = world.groups[id]
			if g.moving and not campaign.send_to(id,g.target): g.moving = false
	$Tools.choose(null)
	for control in [$Bar/Pause,$Bar/Speed,$Bar/Bridge,$Bar/Demo]:
		control.disabled = active
	$Help.text = "ЛКМ — вибрати або перетягнути   •   Розмістити — додати з каталогу" if active else "ЛКМ — точка призначення   •   Колесо — масштаб   •   ПКМ — огляд"
	notice = "Режим редактора" if active else ("Карта має незбережені зміни" if $Tools.dirty else "")
	_refresh()

func set_zoom(close: bool,focus: Vector2) -> void:
	detail = close
	landscape.detailed = close
	landscape.queue_redraw()
	camera.zoom = Vector2.ONE*(1.8 if close else 1.0)
	cart.scale = Vector2.ONE*(0.20 if close else 0.18)
	camera.position = focus
	_camera_bounds()

func _camera_bounds() -> void:
	if camera == null: return
	var half := Vector2($Frame/View.size)*0.5/camera.zoom
	var center := valley.bounds.get_center()
	half = half.min(center)
	camera.position = camera.position.clamp(half,valley.bounds.size-half)
	camera.force_update_scroll()

func _map_input(event: InputEvent) -> void:
	if $Tools.visible and (event is InputEventMouseButton or event is InputEventMouseMotion):
		if $Tools.handle(event,$Frame/View.get_canvas_transform().affine_inverse()*event.position): return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		camera.position -= event.relative/camera.zoom
		_camera_bounds()
	elif event is InputEventMouseButton and event.pressed:
		var pos: Vector2 = $Frame/View.get_canvas_transform().affine_inverse()*event.position
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				order(pos)
			MOUSE_BUTTON_WHEEL_UP: set_zoom(true,pos)
			MOUSE_BUTTON_WHEEL_DOWN: set_zoom(false,pos)

func order(target: Vector2) -> bool:
	var ok := campaign.issue_cart(target) if action=="order" else campaign.send_to(focus_id,target)
	notice = ("Наказ прийнято" if ok else "Ця точка недоступна або посильний далеко")
	_refresh()
	return ok

func _bridge() -> void:
	var id := ""
	var nearest := INF
	for key in valley.crossings:
		var dist: float = world.groups["lord"].position.distance_to(valley.crossings[key].get_center())
		if campaign.live.has(key) and dist<nearest:
			nearest = dist
			id = key
	if id.is_empty(): notice = "Переправу потрібно побачити особисто"
	else: notice = "Стан переправи змінено" if campaign.toggle_gate(id) else "Переправа зайнята"
	_refresh()

func _pause() -> void:
	paused = not paused
	$Bar/Pause.text = "Продовжити" if paused else "Пауза"

func _rate() -> void:
	rate_index = (rate_index+1)%valley.data.rates.size()
	_refresh()

func _process(delta: float) -> void:
	if camera != null and not get_viewport().gui_get_focus_owner() is LineEdit:
		var dir := Vector2(
			int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))-int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
			int(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))-int(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
		if dir!=Vector2.ZERO:
			camera.position += dir.normalized()*460*delta/camera.zoom
			_camera_bounds()
	if paused or $Tools.visible or group == null: return
	remainder += delta*float(valley.data.rates[rate_index])
	var elapsed := floori(remainder)
	if elapsed < 1: return
	remainder -= elapsed
	var convoy: World.Group = world.groups[CART]
	var before := convoy.position
	campaign.advance(elapsed)
	if before != convoy.position:
		if absf(before.x-convoy.position.x)>0.001: cart.flip_h = before.x>convoy.position.x
		wheel_angle = fmod(wheel_angle+before.distance_to(convoy.position)*0.12,TAU)
		wheel.set_shader_parameter("angle",wheel_angle)
	_refresh()

func _refresh() -> void:
	var editing: bool = $Tools.visible
	if not editing: campaign.observe()
	var lord: Vector2 = world.groups["lord"].position
	for id in figures:
		figures[id].position = world.groups[id].position
		figures[id].visible = editing or campaign.live.has(id)
	for id in sites:
		sites[id].visible = editing or campaign.knowledge.has(id)
		sites[id].modulate = Color.WHITE if editing or campaign.live.has(id) else Color("#b1aca1")
	var gates := {}
	for id in valley.crossings:
		if editing: gates[id] = valley.gates[id]
		elif campaign.knowledge.has(id): gates[id] = campaign.knowledge[id].state
	if landscape.known_gates!=gates:
		landscape.known_gates = gates
		landscape.queue_redraw()
	var phase := world.phase()
	tint.color = Color(campaign.config.sight.phases[phase].color)
	fog.visible = not editing
	if not editing and (lord.distance_to(last_fog)>2 or last_phase!=phase):
		fog.update_view(lord,phase,campaign.sight)
		last_fog = lord
		last_phase = phase
	path.visible = group.moving and campaign.live.has(focus_id) and focus_id=="lord"
	marker.visible = path.visible
	if path.visible:
		path.points = group.path
		marker.position = group.target
	var t := (world.time_seconds+21600)%86400
	$Bar/Clock.text = "День %d · %02d:%02d:%02d · %s" % [1+int((world.time_seconds+21600)/86400),int(t/3600),int(t/60)%60,t%60,PHASES[phase]]
	$Bar/Speed.text = "Час ×%d" % int(valley.data.rates[rate_index])
	$Bar/Bridge.text = "Змінити переправу"
	$Status.text = "%s · Огляд %d м · %s" % [definitions[focus_id].name,roundi(campaign.sight.radius(lord,phase)),notice]
