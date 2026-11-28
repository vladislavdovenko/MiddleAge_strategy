extends VBoxContainer

signal feedback(message: String)
const Objects = preload("res://editor/objects.gd")
var objects: Objects
var names: Dictionary
var selected: Sprite2D
var palette := OptionButton.new()
var inventory := OptionButton.new()
var place := Button.new()
var scale_box := SpinBox.new()
var layers := SpinBox.new()
var mirror_h := CheckButton.new()
var mirror_v := CheckButton.new()
var remove_button := Button.new()
var dirty := false
var syncing := false
var dragging := false
var grab_offset := Vector2.ZERO
var outline := Line2D.new()

func label(row: Control, title: String) -> void:
	var item := Label.new()
	item.text = title
	row.add_child(item)

func setup(store: Objects, labels: Dictionary) -> void:
	objects = store
	names = labels
	outline.width = 1.6
	outline.default_color = Color("#9c4d35")
	outline.closed = true
	outline.z_index = 16
	objects.add_child(outline)
	var row := HBoxContainer.new()
	add_child(row)
	label(row,"  Каталог")
	row.add_child(palette)
	for key in names:
		palette.add_item(names[key])
		palette.set_item_metadata(palette.item_count-1,key)
	place.text = "Розмістити"
	place.toggle_mode = true
	row.add_child(place)
	label(row,"  На карті")
	row.add_child(inventory)
	inventory.item_selected.connect(func(i: int): choose(objects.sprites.get(inventory.get_item_metadata(i))))
	var save := Button.new()
	save.text = "Зберегти карту"
	row.add_child(save)
	save.pressed.connect(_save)
	var props := HBoxContainer.new()
	add_child(props)
	label(props,"  Розмір")
	scale_box.min_value = Objects.MIN_SCALE*100
	scale_box.max_value = Objects.MAX_SCALE*100
	scale_box.suffix = "%"
	props.add_child(scale_box)
	label(props,"  Шар")
	layers.min_value = 1
	layers.max_value = 10
	props.add_child(layers)
	mirror_h.text = "Ліво ↔ право"
	mirror_v.text = "Верх ↕ низ"
	props.add_child(mirror_h)
	props.add_child(mirror_v)
	remove_button.text = "Видалити"
	props.add_child(remove_button)
	remove_button.pressed.connect(_delete)
	scale_box.value_changed.connect(func(_v): _apply())
	layers.value_changed.connect(func(_v): _apply())
	mirror_h.toggled.connect(func(_v): _apply())
	mirror_v.toggled.connect(func(_v): _apply())
	refresh_list()
	choose(null)

func refresh_list() -> void:
	inventory.clear()
	inventory.add_item("Вибрати об’єкт")
	for id in objects.sprites:
		var s: Sprite2D = objects.sprites[id]
		inventory.add_item("%s · %s" % [names[s.get_meta("asset")],id])
		inventory.set_item_metadata(inventory.item_count-1,id)

func choose(s: Sprite2D) -> void:
	selected = s
	dragging = false
	place.button_pressed = false
	syncing = true
	scale_box.editable = s != null
	layers.editable = s != null
	mirror_h.disabled = s == null
	mirror_v.disabled = s == null
	remove_button.disabled = s == null
	inventory.select(0)
	if s != null:
		scale_box.value = s.scale.x*100
		layers.value = s.z_index
		mirror_h.button_pressed = s.flip_h
		mirror_v.button_pressed = s.flip_v
		for i in range(1,inventory.item_count):
			if inventory.get_item_metadata(i) == s.get_meta("object_id"): inventory.select(i)
	syncing = false
	mark_bounds()

func mark_bounds() -> void:
	outline.visible = selected != null and visible
	if not outline.visible: return
	var rect := selected.get_rect()
	outline.points = PackedVector2Array([selected.to_global(rect.position),selected.to_global(Vector2(rect.end.x,rect.position.y)),selected.to_global(rect.end),selected.to_global(Vector2(rect.position.x,rect.end.y))])

func _apply() -> void:
	if syncing or selected == null: return
	selected.scale = Vector2.ONE * scale_box.value/100
	selected.z_index = int(layers.value)
	selected.flip_h = mirror_h.button_pressed
	selected.flip_v = mirror_v.button_pressed
	dirty = true
	mark_bounds()

func _delete() -> void:
	if selected == null: return
	objects.remove_object(selected)
	refresh_list()
	choose(null)
	dirty = true

func _save() -> void:
	var err := objects.save_layout()
	if err == OK:
		dirty = false
		feedback.emit("Карту збережено. Вона відкриється при наступному запуску.")
	else:
		feedback.emit("Не вдалося зберегти карту: "+error_string(err))

func handle(event: InputEvent, pos: Vector2) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			dragging = false
		elif place.button_pressed and objects.bounds.has_point(pos):
			var s := objects.create(palette.get_item_metadata(palette.selected),pos)
			refresh_list()
			choose(s)
			dirty = true
		else:
			choose(objects.pick(pos))
			if selected != null:
				grab_offset = selected.position-pos
				dragging = true
		return true
	if event is InputEventMouseMotion and dragging:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			selected.position = (pos+grab_offset).clamp(objects.bounds.position,objects.bounds.end-Vector2.ONE*0.01)
			dirty = true
			mark_bounds()
		else: dragging = false
		return true
	return false
