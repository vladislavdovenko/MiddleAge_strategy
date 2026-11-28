extends Node2D

var valley
var detailed := false
var paper := Color("#e0c995")
var ink := Color("#675438")

func polygon(points: Array,color: String) -> void:
	draw_colored_polygon(PackedVector2Array(points),Color(color))

func cottage(p: Vector2, scale_factor: float) -> void:
	draw_set_transform(p,0,Vector2.ONE*scale_factor)
	polygon([Vector2(-13,0),Vector2(12,0),Vector2(12,-15),Vector2(-13,-15)],"#d4b784")
	polygon([Vector2(-17,-13),Vector2(-6,-26),Vector2(8,-26),Vector2(16,-13)],"#915739")
	draw_line(Vector2(-17,-13),Vector2(-6,-26),ink,1.6,true)
	draw_rect(Rect2(-1,-9,5,9),ink)
	draw_rect(Rect2(-8,-10,3,4),Color("#5c6357"))
	draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	if valley == null: return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1529
	draw_rect(valley.bounds,paper)
	for i in 1700:
		var p := Vector2(rng.randf_range(0,960),rng.randf_range(0,540))
		draw_circle(p,rng.randf_range(2,12),Color(0.44,0.40,0.22,0.025))
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
	for i in 350:
		var p := Vector2(rng.randf_range(6,953),rng.randf_range(12,530))
		draw_polyline(PackedVector2Array([p+Vector2(-2,-2),p,p+Vector2(1,-4)]),Color("#a7a270"),0.8,true)
	draw_colored_polygon(valley.river,Color("#83a99e"))
	for bank in [valley.left,valley.right]:
		draw_polyline(bank,Color("#546f63"),2,true)
	for i in 165:
		var y := rng.randf_range(2,538)
		var x: float = valley.bank_x(y)+rng.randf_range(4,50)
		draw_line(Vector2(x,y),Vector2(x+rng.randf_range(3,9),y-1),Color("#afc8b2"),1,true)
	var y: float = valley.road_y
	var bx: float = valley.bridge.position.x
	var ex: float = valley.bridge.end.x
	for ends in [[0,bx],[ex,960]]:
		draw_rect(Rect2(ends[0],y-valley.data.road_half_height,ends[1]-ends[0],valley.data.road_half_height*2),Color("#ceb087"))
		for off in [-6,6]:
			draw_line(Vector2(ends[0],y+off),Vector2(ends[1],y+off),Color("#ad8e66"),1,true)
	draw_rect(valley.bridge,Color("#af8253"))
	if not detailed:
		draw_arc(Vector2((bx+ex)*0.5,y+6),12,PI,TAU,18,Color("#705138"),3,true)
	if detailed:
		for i in range(int(bx),int(ex),5):
			draw_line(Vector2(i,y-13),Vector2(i+1,y+13),ink,1,true)
	for off in [-13,13]:
		draw_line(Vector2(bx-4,y+off),Vector2(ex+4,y+off),ink,2,true)
		for x in [bx,ex]: draw_circle(Vector2(x,y+off),2.3,ink)
	if not valley.bridge_open:
		draw_line(Vector2(bx,y-12),Vector2(bx,y+12),Color("#963c30"),5,true)
	for home in [Vector2(118,228),Vector2(143,219),Vector2(161,238),Vector2(764,227),Vector2(793,240)]:
		cottage(home,1.0 if detailed else 0.75)
	# A small fortified manor overlooks the eastern approach.
	var manor := Vector2(826,161)
	draw_set_transform(manor)
	polygon([Vector2(-24,0),Vector2(18,0),Vector2(18,-15),Vector2(-24,-15)],"#baa783")
	for tx in [-23,0,18]:
		var height := 28 if tx == 0 else 21
		draw_rect(Rect2(tx-4,-height,9,height),Color("#c6b998"))
		polygon([Vector2(tx-6,-height),Vector2(tx,-height-10),Vector2(tx+7,-height)],"#895843")
		draw_line(Vector2(tx,-height+4),Vector2(tx,-height+8),ink,1.6)
	draw_set_transform(Vector2.ZERO)
	for item in [[Vector2(85,192),"Вільшани"],[Vector2(728,202),"Млинів"],[Vector2(458,356),"Рін"]]:
		draw_string(ThemeDB.fallback_font,item[0],item[1],HORIZONTAL_ALIGNMENT_LEFT,-1,13,ink)
