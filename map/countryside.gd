extends Node2D

var known_gates := {}
var valley
var detailed := false
var paper := Color("#e0c995")
var ink := Color("#675438")

func polygon(points: Array,color: String) -> void:
	draw_colored_polygon(PackedVector2Array(points),Color(color))

func _draw() -> void:
	if valley == null: return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1529
	draw_rect(valley.bounds,paper)
	for i in 5900:
		var p := Vector2(rng.randf_range(0,valley.bounds.end.x),rng.randf_range(0,valley.bounds.end.y))
		draw_circle(p,rng.randf_range(1,7),Color(0.44,0.40,0.22,0.014))
	# Short contours gather into ridges, leaving the road and floodplain open.
	for ridge: Vector2 in [Vector2(115,65),Vector2(312,155),Vector2(610,78),Vector2(785,356),Vector2(279,478)]:
		for j in 4:
			var p := ridge+Vector2(24*j,5*sin(j*1.6))
			var line := PackedVector2Array()
			for k in 17:
				var h := sin(PI*k/16.0)*(12+j*2)
				line.append(p+Vector2(k*2.5,-h))
				if k%3==1:
					draw_line(p+Vector2(k*2.5,-h+2),p+Vector2(k*2.5-4,-h+7),Color("#b0a376"),1,true)
			draw_polyline(line,Color("#a39567"),1.1,true)
	for field in [Vector2(40,360),Vector2(126,388),Vector2(588,122),Vector2(720,109),Vector2(633,394)]:
		var dx := Vector2(81,-15)
		var dy := Vector2(18,37)
		polygon([field,field+dx,field+dx+dy,field+dy],"#c6b271")
		for j in 13:
			var at: Vector2 = field+dx*j/13.0
			draw_line(at,at+dy,Color("#a7935b"),1.1,true)
	for i in 1200:
		var p := Vector2(rng.randf_range(6,valley.bounds.end.x-6),rng.randf_range(12,valley.bounds.end.y-10))
		draw_polyline(PackedVector2Array([p+Vector2(-2,-2),p,p+Vector2(1,-4)]),Color("#a7a270"),0.8,true)
	for zone in valley.data.zones:
		var r: Rect2 = valley.zone_rect(zone)
		var info: Dictionary = valley.data.surfaces[zone.kind]
		draw_rect(r,Color(info.color))
		for i in int(r.get_area()/400):
			var spot := r.position+Vector2(rng.randf(),rng.randf())*r.size
			var shape := PackedVector2Array([spot+Vector2(-3,2),spot+Vector2(0,-4),spot+Vector2(4,2)])
			if zone.kind in ["marsh","deep_marsh"]:
				draw_line(spot-Vector2(3,0),spot+Vector2(3,0),ink,0.7,true)
			else: draw_polyline(shape,ink,0.9,true)
		draw_string(ThemeDB.fallback_font,r.position+Vector2(4,15),info.label,HORIZONTAL_ALIGNMENT_LEFT,int(r.size.x)-6,11,ink)
	for water in valley.waterways:
		draw_colored_polygon(water,Color("#83a99e"))
		draw_polyline(water,Color("#546f63"),2,true)
	for strip in valley.roads:
		draw_colored_polygon(strip,Color("#ceb087"))
	for id in valley.crossings:
		var r: Rect2 = valley.crossings[id]
		draw_rect(r,Color("#af8253"))
		for x in range(int(r.position.x),int(r.end.x),5):
			draw_line(Vector2(x,r.position.y),Vector2(x+1,r.end.y),ink,1,true)
		if known_gates.has(id) and not known_gates[id]:
			draw_line(r.position,Vector2(r.position.x,r.end.y),Color("#963c30"),5,true)
	for item in valley.data.labels:
		draw_string(ThemeDB.fallback_font,Vector2(item[0],item[1]),item[2],HORIZONTAL_ALIGNMENT_LEFT,-1,13,ink)
