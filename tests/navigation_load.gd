extends SceneTree

const Map = preload("res://map/valley.gd")
const World = preload("res://sim/world.gd")

func _initialize() -> void:
	var map := Map.new()
	var world := World.new()
	for i in 32:
		map.data.zones.append({"kind":"forest","x":980+(i%8)*95,"y":590+int(i/8)*100,"w":30,"h":45})
	var began := Time.get_ticks_msec()
	map.rebuild_graph()
	var built := Time.get_ticks_msec()
	for i in 80:
		var id := "group-%d" % i
		var start := Vector2(40+i*2,245)
		world.add_group(id,start,2)
		var route := map.route(start,Vector2(700+i*2,265),2)
		if route.is_empty() or not world.follow_route(id,route.points,route.times):
			printerr("Load fixture could not place a route")
			quit(1)
			return
	var routed := Time.get_ticks_msec()
	world.advance(2000)
	print("NAV_BENCH nodes=%d groups=80 build_ms=%d routes_ms=%d arrived=%d" % [map.graph.get_point_count(),built-began,routed-built,world.arrivals.size()])
	quit(0 if world.arrivals.size()==80 else 1)
