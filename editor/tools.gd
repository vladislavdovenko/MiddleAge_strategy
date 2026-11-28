extends VBoxContainer

signal surfaces_changed
var brush := OptionButton.new()
var first_corner := Vector2.INF
var occupied := Vector2.INF
var occupied_points := PackedVector2Array()
signal feedback(message: String)
const Objects = preload("res://map/objects.gd")
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
	var terrain_row := HBoxContainer.new()
	add_child(terrain_row)
	label(terrain_row,"  Місцевість")
	terrain_row.add_child(brush)
	brush.add_item("Редагувати об’єкти")
	for k in store.map_data.surfaces:
		brush.add_item(store.map_data.surfaces[k].label)
		brush.set_item_metadata(brush.item_count-1,k)
	brush.add_item("Стерти ділянку")
	brush.set_item_metadata(brush.item_count-1,"erase")
	brush.item_selected.connect(func(_i): first_corner = Vector2.INF; choose(null))
	place.toggled.connect(func(on): 
		if on: brush.select(0); first_corner = Vector2.INF)
	label(terrain_row,"Ділянка — два протилежні кути")
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
	var err := objects.save_layout(objects.layout_path)
	if err == OK:
		dirty = false
		feedback.emit("Карту збережено. Вона відкриється при наступному запуску.")
	else:
		feedback.emit("Не вдалося зберегти карту: "+error_string(err))

func handle(event: InputEvent, pos: Vector2) -> bool:
	if brush.selected>0 and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if not event.pressed or not objects.bounds.has_point(pos): return true
		var kind: String = brush.get_item_metadata(brush.selected)
		var zones: Array = objects.map_data.zones
		if kind == "erase":
			for i in range(zones.size()-1,-1,-1):
				var z: Dictionary = zones[i]
				if Rect2(z.x,z.y,z.w,z.h).has_point(pos):
					zones.remove_at(i)
					dirty = true
					surfaces_changed.emit()
					break
		elif first_corner == Vector2.INF:
			first_corner = pos
			feedback.emit("Тепер клацніть протилежний кут")
		else:
			var r := Rect2(first_corner,pos-first_corner).abs()
			first_corner = Vector2.INF
			if r.size.x < 2 or r.size.y < 2: return true
			var occupied_area := r.has_point(occupied)
			for p in occupied_points: occupied_area = occupied_area or r.has_point(p)
			if objects.map_data.surfaces[kind].factor == 0 and occupied_area:
				feedback.emit("Спершу відведіть людей і обоз із цієї ділянки")
				return true
			zones.append({"kind":kind,"x":r.position.x,"y":r.position.y,"w":r.size.x,"h":r.size.y})
			dirty = true
			surfaces_changed.emit()
		return true
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
