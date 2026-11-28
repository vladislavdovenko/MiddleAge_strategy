extends Node2D

const SAVE_PATH := "user://valley-objects-v1.json"
var layout_path: String = SAVE_PATH
const MIN_SCALE := 0.05
const MAX_SCALE := 4.0
var map_data: Dictionary
var textures := {}
var sprites := {}
var bounds: Rect2
var next_id := 1
var read_error := ""

func setup(data: Dictionary, area: Rect2, file_path: String = SAVE_PATH) -> void:
	map_data = data
	y_sort_enabled = true
	bounds = area
	for key in data.assets:
		textures[key] = load(data.assets[key])
	var rows: Array = data.objects
	if FileAccess.file_exists(file_path):
		var candidate = JSON.parse_string(FileAccess.get_file_as_string(file_path))
		if valid_package(candidate):
			rows = candidate.objects
			if candidate.has("zones"): data.zones = candidate.zones
		else:
			read_error = "Помилка файлу карти. Відкрито початкову карту."
	for row in rows:
		insert(row)

func valid_package(package: Variant) -> bool:
	if not package is Dictionary or package.get("version") != 1 or not package.get("objects") is Array:
		return false
	if package.has("zones"):
		if not package.zones is Array: return false
		for zone in package.zones:
			if not zone is Dictionary or not map_data.surfaces.has(zone.get("kind","")): return false
			for k in ["x","y","w","h"]:
				if typeof(zone.get(k)) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(zone[k])): return false
			var rect := Rect2(zone.x,zone.y,zone.w,zone.h)
			if not rect.has_area() or not bounds.encloses(rect): return false
	var ids := {}
	for row in package.objects:
		if not row is Dictionary: return false
		if not row.get("id") is String or row.id.is_empty() or ids.has(row.id): return false
		if not row.get("asset") is String or not textures.has(row.asset): return false
		for k in ["x","y","scale","layer"]:
			if typeof(row.get(k)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(row[k])): return false
		if not bounds.has_point(Vector2(row.x,row.y)) or row.scale < MIN_SCALE or row.scale > MAX_SCALE: return false
		if row.layer != int(row.layer) or row.layer < 1 or row.layer > 10: return false
		if not row.get("flip_h") is bool or not row.get("flip_v") is bool: return false
		ids[row.id] = true
	return true

func insert(row: Dictionary) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = textures[row.asset]
	sprite.offset.y = -sprite.texture.get_height()*0.5
	sprite.position = Vector2(row.x,row.y)
	sprite.scale = Vector2.ONE * float(row.scale)
	sprite.z_index = int(row.layer)
	sprite.flip_h = row.flip_h
	sprite.flip_v = row.flip_v
	sprite.set_meta("asset",row.asset)
	sprite.set_meta("object_id",row.id)
	sprites[row.id] = sprite
	add_child(sprite)
	return sprite

func create(asset: String, pos: Vector2) -> Sprite2D:
	while sprites.has("new-%d" % next_id): next_id += 1
	var row := {"id":"new-%d" % next_id,"asset":asset,"x":pos.x,"y":pos.y,"scale":0.5,"layer":5,"flip_h":false,"flip_v":false}
	next_id += 1
	return insert(row)

func remove_object(sprite: Sprite2D) -> void:
	sprites.erase(sprite.get_meta("object_id"))
	remove_child(sprite)
	sprite.queue_free()

func in_front(a: Sprite2D,b: Sprite2D) -> bool:
	if a.z_index != b.z_index: return a.z_index > b.z_index
	if a.position.y != b.position.y: return a.position.y > b.position.y
	return a.get_index() > b.get_index()

func pick(pos: Vector2) -> Sprite2D:
	var found: Sprite2D
	for sprite: Sprite2D in sprites.values():
		if sprite.get_rect().has_point(sprite.to_local(pos)) and sprite.is_pixel_opaque(sprite.to_local(pos)) and (found == null or in_front(sprite,found)):
			found = sprite
	return found

func save_layout(file_path: String = SAVE_PATH) -> Error:
	var rows := []
	for id in sprites:
		var s: Sprite2D = sprites[id]
		rows.append({"id":id,"asset":s.get_meta("asset"),"x":s.position.x,"y":s.position.y,"scale":s.scale.x,"layer":s.z_index,"flip_h":s.flip_h,"flip_v":s.flip_v})
	var tmp := file_path + ".tmp"
	var f := FileAccess.open(tmp,FileAccess.WRITE)
	if f == null: return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"version":1,"objects":rows,"zones":map_data.zones},"  "))
	f.flush()
	var err := f.get_error()
	f.close()
	if err != OK: return err
	return DirAccess.rename_absolute(tmp,file_path)
