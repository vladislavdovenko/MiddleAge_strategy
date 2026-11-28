extends Node2D

const Geo = preload("res://region/geography.gd")
const Market = preload("res://region/market.gd")
var geo:=Geo.new()
var market:=Market.new()
var features:=preload("res://region/features.gd").new()
var objects:=preload("res://map/objects.gd").new()
var editor:=preload("res://editor/tools.gd").new()
var cam:=Camera2D.new()
var tint:=CanvasModulate.new()
var panel:=VBoxContainer.new()
var card:=Label.new()
var status:=Label.new()
var controls:=HBoxContainer.new()
var actors: Array[Sprite2D]=[]
var patrol_art: Array[Sprite2D]=[]
var band_art: Array[Sprite2D]=[]
var zoom_level:=5
var rates: Array=[1,10,60,300,600]
var rate:=2
var paused:=false
var debt:=0.0
var hovered: Dictionary={}
var labels: Array[Label]=[]
var notice:=""
var editor_path: String
var ready_map:=false

func button(title: String,cb: Callable) -> Button:
	var b:=Button.new()
	b.text=title
	controls.add_child(b)
	b.pressed.connect(cb)
	return b

func _ready() -> void:
	var ui:=CanvasLayer.new()
	add_child(ui)
	ui.add_child(panel)
	panel.position=Vector2(10,8)
	panel.add_child(controls)
	panel.add_child(status)
	panel.add_child(editor)
	panel.add_child(card)
	card.add_theme_stylebox_override("normal",box())
	status.add_theme_stylebox_override("normal",box())
	card.hide()
	editor.hide()
	var file: String=ProjectSettings.globalize_path("res://region/world.png") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("world.png")
	var img:=Image.load_from_file(file)
	if img==null or img.is_empty():
		status.text="Покладіть world.png поруч із програмою і відкрийте її знову."
		return
	var rules: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://region/rules.json"))
	geo.generate(img,rules)
	if not geo.error.is_empty():
		status.text=geo.error
		return
	market.setup(geo)
	add_child(tint)
	make_ground()
	features.geo=geo
	add_child(features)
	add_child(objects)
	var rows: Array=[]
	var types:=["oak","apple","spire"]
	for tree in geo.trees:
		rows.append({"id":"tree-"+str(rows.size()),"asset":types[tree.type],"x":tree.p.x,"y":tree.p.y,"scale":tree.scale,"layer":5,"flip_h":rows.size()%2==0,"flip_v":false})
	var assets: Dictionary={}
	for key in ["oak","apple","spire","manor","cottage","cart"]:
		assets[key]="res://art/"+key+(".svg" if key in ["manor","cottage"] else ".webp")
	editor_path="user://region-"+geo.fingerprint+".json"
	objects.layout_path=editor_path
	objects.setup({"assets":assets,"objects":rows,"zones":[],"surfaces":{}},Rect2(Vector2.ZERO,Vector2(geo.size)*geo.cell),editor_path)
	editor.setup(objects,{"oak":"Дуб","apple":"Яблуня","spire":"Тополя","manor":"Двір","cottage":"Хата","cart":"Віз"})
	editor.brush.get_parent().hide()
	editor.feedback.connect(func(msg): notice=msg)
	rebuild_obstacles()
	for t in geo.towns:
		var center:=geo.pos(t.p)
		sprite(load(assets.manor if t.kind=="town" else assets.cottage),center,1.2 if t.kind=="town" else 1.0)
		for j in (7 if t.kind=="town" else 3):
			var offset:=Vector2.RIGHT.rotated(j*2.4)*geo.rng.randf_range(20,52)
			sprite(load(assets.cottage),center+offset,geo.rng.randf_range(.48,.85))
		var label:=Label.new()
		label.text=t.name
		label.position=center+Vector2(-25,5)
		label.add_theme_constant_override("outline_size",4)
		label.add_theme_color_override("font_outline_color",Color("#4a3826"))
		label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		label.z_index=10
		add_child(label)
		labels.append(label)
	for c in market.carts:
		actors.append(sprite(load(assets.cart),c.p,.24))
		var rider:=sprite(preload("res://region/assets/rider.webp"),c.p,.52)
		actors[-1].set_meta("rider",rider)
	for camp in market.watch.camps:
		var center:=geo.pos(camp.p)
		sprite(preload("res://art/cottage.svg"),center,.82)
		if camp.kind=="garrison": sprite(preload("res://region/assets/standard.webp"),center+Vector2(22,3),.32)
	for guard in market.watch.guards: patrol_art.append(sprite(preload("res://region/assets/guard.webp"),guard.p,.40))
	for band in market.watch.bands: band_art.append(sprite(preload("res://region/assets/traveller.webp"),band.p,.38))
	add_child(cam)
	cam.position=geo.pos(geo.towns[0].p)
	cam.zoom=Vector2.ONE*zoom_factor()
	cam.enabled=true
	button("Пауза",func(): paused=not paused)
	var speed:=button("×60",func(): rate=(rate+1)%rates.size())
	speed.pressed.connect(func(): speed.text="×"+str(rates[rate]))
	button("−",func(): zoom_level=clampi(zoom_level-1,0,13))
	button("+",func(): zoom_level=clampi(zoom_level+1,0,13))
	button("Вся карта",func(): zoom_level=0; cam.position=Vector2(geo.size)*geo.cell/2)
	button("Редактор",func():
		editor.visible=not editor.visible
		editor.choose(null)
		if not editor.visible: rebuild_obstacles())
	button("Зберегти",save_market)
	button("Відновити",load_market)
	button("Полігон феодала",func(): get_tree().change_scene_to_file("res://main.tscn"))
	notice="Наведіть на поселення · клацніть міст, щоб змінити стан"
	ready_map=true
	print("REGION_READY ",geo.fingerprint," settlements=",geo.towns.size()," merchants=",market.carts.size())

func box() -> StyleBoxFlat:
	var b:=StyleBoxFlat.new()
	b.bg_color=Color("#322d26ed")
	b.content_margin_left=10
	b.content_margin_right=10
	b.content_margin_top=5
	b.content_margin_bottom=5
	return b

func sprite(texture: Texture2D,p: Vector2,s: float) -> Sprite2D:
	var obj:=Sprite2D.new()
	obj.texture=texture
	obj.offset.y=-texture.get_height()/2.0
	obj.scale=Vector2.ONE*s
	obj.z_index=5
	obj.position=p
	objects.add_child(obj)
	return obj

func rebuild_obstacles() -> void:
	geo.obstacles.clear()
	for obj in objects.sprites.values():
		var p: Vector2=obj.position
		var k:=Vector2i(p/geo.cell)
		if not geo.obstacles.has(k): geo.obstacles[k]=[]
		geo.obstacles[k].append(p)

func make_ground() -> void:
	var mask:=Image.create_empty(geo.size.x,geo.size.y,false,Image.FORMAT_RGB8)
	for p in geo.land:
		var k: String=geo.land[p]
		mask.set_pixelv(p,Color(float({"forest":.6,"mountain":.9,"grain":.72,"marsh":.45}.get(k,.04)),1.0 if k in ["river","bridge"] else (.28 if k=="marsh" else 0.0),0))
	var rect:=ColorRect.new()
	rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rect.size=Vector2(geo.size)*geo.cell
	var mat:=ShaderMaterial.new()
	mat.shader=preload("res://region/ground.gdshader")
	for k in ["grass","earth","track","water"]:
		mat.set_shader_parameter("water_tex" if k=="water" else k,load("res://region/assets/"+k+".webp"))
	mat.set_shader_parameter("masks",ImageTexture.create_from_image(mask))
	mat.set_shader_parameter("world_size",rect.size)
	rect.material=mat
	add_child(rect)

func zoom_factor() -> float:
	return minf(get_viewport_rect().size.x/(geo.size.x*geo.cell),get_viewport_rect().size.y/(geo.size.y*geo.cell))*pow(1.24,zoom_level)

func _unhandled_input(e: InputEvent) -> void:
	if not ready_map: return
	var p:=get_global_mouse_position()
	if editor.visible and (e is InputEventMouseButton or e is InputEventMouseMotion):
		if editor.handle(e,p): return
	if e is InputEventMouseMotion and e.button_mask&MOUSE_BUTTON_MASK_RIGHT:
		cam.position-=e.relative/cam.zoom
	if e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_WHEEL_UP: zoom_level=clampi(zoom_level+1,0,13)
			MOUSE_BUTTON_WHEEL_DOWN: zoom_level=clampi(zoom_level-1,0,13)
			MOUSE_BUTTON_LEFT:
				for bridge in geo.bridges:
					if geo.pos(bridge).distance_to(p)>maxf(42,12/cam.zoom.x): continue
					if market.toggle(bridge):
						notice="Переправу відкрито" if geo.bridges[bridge].open else "Переправу закрито"
						features.queue_redraw()
					else: notice="На переправі віз"
					break

func _process(dt: float) -> void:
	if not ready_map: return
	cam.zoom=cam.zoom.lerp(Vector2.ONE*zoom_factor(),1-exp(-12*dt))
	var dir:=Input.get_vector("ui_left","ui_right","ui_up","ui_down")
	if Input.is_key_pressed(KEY_W): dir.y-=1
	if Input.is_key_pressed(KEY_S): dir.y+=1
	if Input.is_key_pressed(KEY_A): dir.x-=1
	if Input.is_key_pressed(KEY_D): dir.x+=1
	cam.position+=dir.limit_length()*550*dt/cam.zoom.x
	var extent:=Vector2(geo.size)*geo.cell
	var half: Vector2=(get_viewport_rect().size/2/cam.zoom).min(extent/2)
	cam.position=cam.position.clamp(half,extent-half)
	if not paused and not editor.visible:
		debt+=dt*float(rates[rate])
		var steps:=mini(120,floori(debt))
		for j in steps: market.advance()
		debt-=steps
	var phase: int=(market.time/21600)%4
	tint.color=Color(geo.rules.phase[phase])
	for i in actors.size():
		var c: Dictionary=market.carts[i]
		var dx: float=c.p.x-actors[i].position.x
		if absf(dx)>.01: actors[i].flip_h=dx<0
		actors[i].position=c.p
		var rider: Sprite2D=actors[i].get_meta("rider")
		rider.flip_h=not actors[i].flip_h
		rider.position=c.p+Vector2(-27 if actors[i].flip_h else 27,1)
	for group in [[market.watch.guards,patrol_art],[market.watch.bands,band_art]]:
		for i in group[0].size():
			var person: Dictionary=group[0][i]
			var art: Sprite2D=group[1][i]
			if absf(art.position.x-person.p.x)>.1: art.flip_h=person.p.x<art.position.x
			art.position=person.p
			art.visible=person.mode!="gone"
	for label in labels: label.scale=Vector2.ONE*clampf(0.72/cam.zoom.x,.7,2.1)
	status.text="День %d · %02d:%02d    Доставок %d    %s" % [1+(market.time+21600)/86400,(6+market.time/3600)%24,market.time/60%60,market.trades,notice]
	var p:=get_global_mouse_position()
	card.hide()
	if editor.visible: return
	for group in [[market.watch.guards,"Варта"],[market.watch.bands,"Розбійники"],[market.carts,"Купець"]]:
		for unit: Dictionary in group[0]:
			if unit.get("mode","")=="gone" or p.distance_to(unit.p)>maxf(25,8/cam.zoom.x): continue
			var modes={"camp":"у таборі","woods":"прямує до лісу","approach":"виходить до дороги","ambush":"у засідці","escape":"відступає до лісу","hidden":"переховується","search":"оглядає місце","investigate":"прямує до останнього місця спостереження","return":"повертається","stranded":"очікує переправи"}
			card.text="%s · %s" % [group[1],modes.get(unit.get("mode",""),unit.get("status",""))]
			if unit.has("good"): card.text+=" · %s %d" % [geo.rules.goods.get(unit.good,"без вантажу"),unit.load]
			for key in unit.memory:
				var fact: Dictionary=unit.memory[key]
				card.text+="\nЗасідка біля (%d, %d) · %d хв тому" % [fact.node%geo.size.x,fact.node/geo.size.x,(market.time-fact.seen)/60]
			if unit.has("trails"): card.text+="\nВідомі об’їзди: %d відтинків · переправи: %d" % [unit.trails.size(),unit.reports.size()]
			card.show()
			return
	for t in geo.towns:
		if p.distance_to(geo.pos(t.p))>maxf(68,13/cam.zoom.x): continue
		var people:=PackedStringArray()
		for i in geo.rules.classes.size():
			people.append("%s %d" % [geo.rules.classes.values()[i],t.people[i]])
		var stock:=PackedStringArray()
		for good in geo.rules.goods: stock.append("%s %d" % [geo.rules.goods[good],t.stocks[good]])
		var sites:=PackedStringArray()
		for good in t.sites: sites.append(geo.rules.goods[good])
		card.text="%s · %s\n%s\nНаселення %d · %s\nЗалежні села: %s\nВиробництво: %s\nЗапаси: %s\nПрибуло вантажів: %d" % [t.name,"місто" if t.kind=="town" else "село",t.owner,t.pop,", ".join(people),", ".join(t.villages),", ".join(sites),", ".join(stock),t.deliveries]
		card.show()
		return
func save_market() -> void:
	var target: String="user://trade-"+geo.fingerprint+".save"
	var f:=FileAccess.open(target+".tmp",FileAccess.WRITE)
	if f==null:
		notice="Не вдалося відкрити файл запису"
		return
	f.store_var(market.snapshot())
	f.flush()
	var err:=f.get_error()
	f.close()
	if err==OK: err=DirAccess.rename_absolute(target+".tmp",target)
	notice="Партію збережено" if err==OK else "Помилка запису партії"

func load_market() -> void:
	var f:=FileAccess.open("user://trade-"+geo.fingerprint+".save",FileAccess.READ)
	if f!=null and market.restore(f.get_var()):
		debt=0
		features.queue_redraw()
		notice="Торгівлю відновлено"
	else: notice="Для цієї карти немає придатного збереження"
