extends RefCounted

const DATA_PATH := "res://data/valley.json"
var data: Dictionary
var regions: Array[Dictionary] = []
var bounds: Rect2
var river := PackedVector2Array()
var left := PackedVector2Array()
var right := PackedVector2Array()
var bridge: Rect2
var bridge_open := true
var road_y: float
var anchors := PackedVector2Array()

static func point(pair: Array) -> Vector2:
	return Vector2(pair[0], pair[1])

func _init() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	bounds = Rect2(Vector2.ZERO, point(data.size))
	for region_file in data.regions:
		var region: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(region_file))
		regions.append(region)
	road_y = data.bridge_y
	for pair in data.river_left:
		var p := point(pair)
		left.append(p)
		right.append(p + Vector2.RIGHT * float(data.river_width))
	river.append_array(left)
	var reverse := right.duplicate()
	reverse.reverse()
	river.append_array(reverse)
	var x := bank_x(road_y)
	bridge = Rect2(x, road_y - data.bridge_half_height, data.river_width, 2 * data.bridge_half_height)
	for i in left.size():
		anchors.append(left[i] + Vector2.LEFT)
		anchors.append(right[i] + Vector2.RIGHT)
	for edge in [-1, 0, 1]:
		var y: float = road_y + edge * float(data.road_half_height)
		anchors.append(Vector2(x, y))
		anchors.append(Vector2(bridge.end.x, y))

func bank_x(y: float) -> float:
	for i in range(1, left.size()):
		if y <= left[i].y:
			var a := left[i-1]
			var b := left[i]
			return lerpf(a.x, b.x, (y-a.y)/(b.y-a.y))
	return left[-1].x

func region_at(p: Vector2) -> String:
	for region in regions:
		var area := Rect2(point(region.origin),point(region.size))
		if area.has_point(p): return region.name
	return ""


func zone_rect(zone: Dictionary) -> Rect2:
	return Rect2(zone.x,zone.y,zone.w,zone.h)

func terrain_at(p: Vector2) -> String:
	var kind := "field"
	var forest := false
	var mountain := false
	var slowest: float = data.field_factor
	for zone in data.zones:
		if not zone_rect(zone).has_point(p): continue
		var k: String = zone.kind
		var f: float = data.surfaces[k].factor
		if f == 0: return k
		forest = forest or k=="forest"
		mountain = mountain or k=="mountains"
		if f < slowest:
			slowest = f
			kind = k
	if absf(p.y-road_y)<=float(data.road_half_height): return "road"
	return "mountain_forest" if mountain and forest else kind

func factor_at(p: Vector2) -> float:
	var kind := terrain_at(p)
	if kind=="road": return data.road_factor
	if kind=="field": return data.field_factor
	return data.surfaces[kind].factor

func walkable(p: Vector2) -> bool:
	if not bounds.has_point(p) or factor_at(p)<=0:
		return false
	var x := bank_x(p.y)
	if p.x <= x + 0.0001 or p.x >= x + float(data.river_width) - 0.0001:
		return true
	return bridge_open and absf(p.y-road_y) <= float(data.bridge_half_height)

# Split at every linear bank bend, bank intersection, bridge boundary and road edge.
# Inside each resulting interval both surface and passability are constant.
func cuts(a: Vector2, b: Vector2) -> Array[float]:
	var ts: Array[float] = [0.0,1.0]
	var delta := b-a
	if absf(delta.y) > 0.00001:
		var levels: Array = [bridge.position.y, bridge.end.y, road_y-data.road_half_height, road_y+data.road_half_height]
		for v in left: levels.append(v.y)
		for y: float in levels:
			var t: float = (y-a.y)/delta.y
			if t>0 and t<1: ts.append(t)
	for bank in [left,right]:
		for i in range(1,bank.size()):
			var hit = Geometry2D.segment_intersects_segment(a,b,bank[i-1],bank[i])
			if hit != null and delta.length_squared()>0:
				ts.append(clampf((Vector2(hit)-a).dot(delta)/delta.length_squared(),0,1))
	for zone in data.zones:
		var rect := zone_rect(zone)
		if not rect.grow(0.01).intersects(Rect2(a,b-a).abs().grow(0.01)): continue
		for axis in 2:
			if absf(delta[axis]) < 0.00001: continue
			for edge: float in [rect.position[axis],rect.end[axis]]:
				var t: float = (edge-a[axis])/delta[axis]
				if t>0 and t<1: ts.append(t)
	ts.sort()
	return ts

func edge_cost(a: Vector2,b: Vector2) -> float:
	if not walkable(a) or not walkable(b): return INF
	var ts := cuts(a,b)
	var distance := a.distance_to(b)
	var cost := 0.0
	for i in range(1,ts.size()):
		if ts[i]-ts[i-1]<0.000001: continue
		var mid := a.lerp(b,(ts[i]+ts[i-1])*0.5)
		if not walkable(mid): return INF
		var factor := factor_at(mid)
		cost += distance*(ts[i]-ts[i-1])/factor
	return cost

class TravelGraph extends AStar2D:
	var costs := {}
	func _compute_cost(a: int,b: int) -> float:
		return costs[Vector2i(mini(a,b),maxi(a,b))]
	func _estimate_cost(_a: int,_b: int) -> float:
		return 0.0

var graph: TravelGraph
var cached_open := true

func connect_if_clear(g: TravelGraph, i: int,j: int) -> void:
	var cost := edge_cost(g.get_point_position(i),g.get_point_position(j))
	if is_finite(cost):
		g.costs[Vector2i(mini(i,j),maxi(i,j))] = cost
		g.connect_points(i,j)

func rebuild_graph() -> void:
	var nodes := anchors.duplicate()
	for zone in data.zones:
		var r := zone_rect(zone).grow(0.25)
		nodes.append_array(PackedVector2Array([r.position,r.end,Vector2(r.end.x,r.position.y),Vector2(r.position.x,r.end.y)]))
	for x in [1,109,845,960,1440,1919]: nodes.append(Vector2(x,road_y))
	graph = TravelGraph.new()
	cached_open = bridge_open
	for i in nodes.size(): graph.add_point(i+2,nodes[i])
	for i in nodes.size():
		for j in range(i+1,nodes.size()): connect_if_clear(graph,i+2,j+2)

func route(a: Vector2,b: Vector2,speed: float) -> Dictionary:
	if speed <= 0 or not walkable(a) or not walkable(b): return {}
	if a.is_equal_approx(b): return {"points":PackedVector2Array([a]),"times":PackedFloat64Array([0])}
	if graph == null or cached_open != bridge_open: rebuild_graph()
	var g := graph
	for id in [0,1]:
		if g.has_point(id): g.remove_point(id)
		g.add_point(id,a if id==0 else b)
	for id in [0,1]:
		for other in g.get_point_ids():
			if other == id or g.are_points_connected(id,other): continue
			connect_if_clear(g,id,other)
	var ids := g.get_id_path(0,1)
	if ids.is_empty(): return {}
	var points := PackedVector2Array([a])
	var times := PackedFloat64Array([0])
	for i in range(1,ids.size()):
		var start := g.get_point_position(ids[i-1])
		var end := g.get_point_position(ids[i])
		for t in cuts(start,end):
			var next := start.lerp(end,t)
			if points[-1].distance_to(next)<0.0001: continue
			times.append(times[-1]+edge_cost(points[-1],next)/speed)
			points.append(next)
	return {"points":points,"times":times}
