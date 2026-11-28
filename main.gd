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
const Objects = preload("res://editor/objects.gd")
var objects := Objects.new()
var cart := Sprite2D.new()
var wheel := ShaderMaterial.new()
var path := Line2D.new()
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
	var speeds := Types.load_speeds()
	if not speeds.has("cart"):
		get_tree().quit(1)
		return
	world.add_group(CART,Valley.point(valley.data.start),speeds.cart)
	group = world.groups[CART]
	camera = $Frame/View/Camera
	$Frame/View/Land.add_child(landscape)
	landscape.valley = valley
	$Frame/View/Land.add_child(objects)
	objects.setup(valley.data,valley.bounds)
	$Tools.setup(objects,valley.data.asset_labels)
	$Tools.feedback.connect(func(message: String): notice = message; _refresh())
	$Bar/Editor.toggled.connect(_edit_mode)
	cart.texture = load(valley.data.assets.cart)
	cart.offset.y = -cart.texture.get_height()*0.5
	cart.scale = Vector2.ONE*0.18
	cart.z_index = valley.data.cart_layer
	wheel.shader = preload("res://map/wheel.gdshader")
	cart.material = wheel
	objects.add_child(cart)
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
	$Bar/Zoom.pressed.connect(func(): set_zoom(not detail,group.position))
	$Bar/Demo.pressed.connect(func(): order(Valley.point(valley.data.demo_target) if group.position.x<valley.bridge.get_center().x else Valley.point(valley.data.start)))
	$Frame.gui_input.connect(_map_input)
	$Frame.resized.connect(_camera_bounds)
	set_zoom(false,group.position)
	order(Valley.point(valley.data.demo_target))

	if not objects.read_error.is_empty():
		notice = objects.read_error
		_refresh()

func _edit_mode(active: bool) -> void:
	$Tools.visible = active
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
	camera.position = focus if close else valley.bounds.get_center()
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
				if Rect2(cart.position-Vector2(30,32),Vector2(60,36)).has_point(pos):
					selected = true
					notice = "Віз вибрано"
					_refresh()
				elif selected: order(pos)
			MOUSE_BUTTON_WHEEL_UP: set_zoom(true,pos)
			MOUSE_BUTTON_WHEEL_DOWN: set_zoom(false,pos)

func order(target: Vector2) -> bool:
	var route := valley.route(group.position,target,group.speed_mps)
	if route.is_empty():
		notice = "Ця точка недоступна"
		_refresh()
		return false
	world.follow_route(CART,route.points,route.times)
	path.points = route.points
	marker.position = target
	notice = ""
	_refresh()
	return true

func _bridge() -> void:
	if valley.bridge_open and valley.bridge.has_point(group.position):
		notice = "Віз на переправі — дочекайтеся виїзду"
	else:
		valley.bridge_open = not valley.bridge_open
		notice = ""
		if group.moving and not order(group.target):
			group.moving = false
			notice = "Переправу закрито. Віз чекає нового маршруту"
		landscape.queue_redraw()
	$Bar/Bridge.text = "Закрити міст" if valley.bridge_open else "Відкрити міст"
	_refresh()

func _pause() -> void:
	paused = not paused
	$Bar/Pause.text = "Продовжити" if paused else "Пауза"

func _rate() -> void:
	rate_index = (rate_index+1)%valley.data.rates.size()
	_refresh()

func _process(delta: float) -> void:
	if paused or $Tools.visible or group == null: return
	remainder += delta*float(valley.data.rates[rate_index])
	var elapsed := floori(remainder)
	if elapsed < 1: return
	remainder -= elapsed
	var before := group.position
	world.advance(elapsed)
	if before != group.position:
		if absf(before.x-group.position.x)>0.001: cart.flip_h = before.x>group.position.x
		wheel_angle = fmod(wheel_angle+before.distance_to(group.position)*0.12,TAU)
		wheel.set_shader_parameter("angle",wheel_angle)
	_refresh()

func _refresh() -> void:
	cart.position = group.position
	marker.visible = group.moving
	path.visible = group.moving
	var t := (world.time_seconds+World.PHASE_SECONDS)%86400
	var day := 1+int((world.time_seconds+21600)/86400)
	$Bar/Clock.text = "День %d · %02d:%02d:%02d · %s" % [day,int(t/3600),int(t/60)%60,t%60,PHASES[world.phase()]]
	$Bar/Speed.text = "Час ×%d" % int(valley.data.rates[rate_index])
	var state := "У дорозі" if group.moving else "На місці"
	$Status.text = "%s   ·   %s   ·   %s" % ["Селянський віз",valley.region_at(group.position),state if notice.is_empty() else notice]
