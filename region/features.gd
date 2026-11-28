extends Node2D

var geo
var track := preload("res://region/assets/track.webp")
var ink := Color("#56442e")

func _draw() -> void:
	if geo==null: return
	texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	for key in geo.segments:
		var a: Vector2=geo.graph.get_point_position(key.x)
		var b: Vector2=geo.graph.get_point_position(key.y)
		var w:=9.0 if geo.segments[key] else 4.0
		var n: Vector2=(b-a).normalized().orthogonal()*w
		draw_line(a,b,Color("#987950"),w*2+2,true)
		var corners:=PackedVector2Array([a-n,b-n,b+n,a+n])
		var uvs:=PackedVector2Array()
		for p in corners: uvs.append(p/160.0)
		draw_polygon(corners,PackedColorArray([Color.WHITE]),uvs,track)
		draw_circle(a,w,Color("#be9c68"))
	for p in geo.bridges:
		var c: Vector2=geo.pos(p)
		var horizontal: bool=geo.land.get(p+Vector2i.RIGHT) in ["road","bridge"] or geo.land.get(p+Vector2i.LEFT) in ["road","bridge"]
		draw_set_transform(c,0.0 if horizontal else PI/2)
		draw_rect(Rect2(-43,-10,86,20),Color("#a27a51"))
		for x in range(-43,43,5): draw_line(Vector2(x,-10),Vector2(x,10),ink,1.5)
		for y in [-11,11]: draw_line(Vector2(-45,y),Vector2(45,y),ink,3)
		if not geo.bridges[p].open: draw_line(Vector2(-30,-12),Vector2(-30,12),Color("#a52e25"),5)
		draw_set_transform(Vector2.ZERO)
	for site in geo.sources:
		var c: Vector2=geo.pos(site.p)
		if site.good=="grain":
			var field:=PackedVector2Array([c+Vector2(-27,-8),c+Vector2(21,-18),c+Vector2(34,7),c+Vector2(-14,17)])
			draw_colored_polygon(field,Color("#be9950"))
			for j in 9:
				var start:=c+Vector2(-25+j*5,-8-j)
				draw_line(start,start+Vector2(13,23),Color("#82633a"),1.3,true)
		else:
			var pigment:=Color(geo.rules.palette[site.good])
			for j in 4:
				var p:=c+Vector2(7*j-13,cos(j*2.0)*5)
				var stone:=PackedVector2Array([p+Vector2(-7,3),p+Vector2(-3,-8),p+Vector2(4,-10),p+Vector2(9,3)])
				draw_colored_polygon(stone,pigment)
				draw_polyline(stone,ink,1.1,true)
