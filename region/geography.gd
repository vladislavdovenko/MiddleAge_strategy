extends RefCounted

var rules: Dictionary
var pixels: Image
var size: Vector2i
var cell: int
var land := {}
var points := {}
var towns: Array[Dictionary] = []
var sources: Array[Dictionary] = []
var trees: Array[Dictionary] = []
var forests := {}
var obstacles := {}
var bridges := {}
var segments := {}
var graph := AStar2D.new()
var builder := AStarGrid2D.new()
var rng := RandomNumberGenerator.new()
var error := ""
var fingerprint: String

func pos(p: Vector2i) -> Vector2:
	return points.get(p,(Vector2(p)+Vector2(0.5,0.5))*cell)

func idx(p: Vector2i) -> int:
	return p.y*size.x+p.x

func generate(img: Image, config: Dictionary) -> void:
	rules=config
	pixels=img
	pixels.convert(Image.FORMAT_RGB8)
	size=img.get_size()
	cell=rules.cell
	if size.x<3 or size.y<3 or size.x>256 or size.y>256:
		error="Розмір PNG має бути від 3 до 256 пікселів на вісь."
		return
	var ctx:=HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(img.get_data())
	fingerprint=ctx.finish().hex_encode()
	rng.seed=fingerprint.left(8).hex_to_int() ^ int(rules.seed)
	var colors: Dictionary={}
	for k in rules.palette: colors[rules.palette[k]]=k
	builder.region=Rect2i(Vector2i.ZERO,size)
	builder.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	builder.update()
	var road_cells: Array=[]
	for y in size.y:
		for x in size.x:
			var p:=Vector2i(x,y)
			var rgb:=img.get_pixel(x,y).to_html(false)
			if not colors.has(rgb):
				error="Невідомий колір #%s у (%d, %d)" % [rgb,x,y]
				return
			var k: String=colors[rgb]
			land[p]=k
			points[p]=(Vector2(p)+Vector2(0.5+rng.randf_range(-0.16,0.16),0.5+rng.randf_range(-0.16,0.16)))*cell
			builder.set_point_solid(p,k=="river")
			builder.set_point_weight_scale(p,{"road":0.5,"bridge":0.5,"forest":2,"marsh":6,"mountain":4}.get(k,1))
			if k in ["town","village"]:
				var n:=towns.size()
				var pop:=rng.randi_range(1000,2400) if k=="town" else rng.randi_range(90,380)
				var name: String=rules.names[n%rules.names.size()]
				if n>=rules.names.size(): name+=" "+str(n+1)
				var workers:=pop/3 if k=="town" else pop/12
				var traders:=workers/4
				towns.append({"p":p,"name":name,"kind":k,"pop":pop,"people":[pop-workers-traders-3,workers,traders,3],"owner":"Війт Мирослав · магдебурзьке право" if k=="town" and n%2==0 else "Власник · рід Вільшанських","villages":[],"sites":[],"stocks":{},"demand":{},"deliveries":0})
			if k=="bridge": bridges[p]={"open":true,"version":0}
			if k in ["road","bridge"]: road_cells.append(p)
			if rules.goods.has(k): sources.append({"p":p,"good":k})
			if k=="forest":
				var primary:=int(absf(sin(x/12.0+y/10.0))*2.99)
				var count:=rng.randi_range(2,5)+roundi(4.0*absf(sin(x/7.0-y/9.0)))
				forests[p]=count
				for j in count:
					var at: Vector2=(Vector2(p)+Vector2(rng.randf(),rng.randf()))*cell
					var scale_value:=rng.randf_range(0.18,0.38)
					trees.append({"p":at,"type":primary if rng.randf()<0.74 else rng.randi_range(0,2),"scale":scale_value})
					if not obstacles.has(p): obstacles[p]=[]
					obstacles[p].append(at)
	if towns.is_empty():
		error="Позначте на карті принаймні одне поселення."
		return
	# A coarse miniature can omit all ore and field markers. Explicit marks
	# take precedence and suppress automatic deposits of the same material.
	var hills: Array=[]
	for p in land:
		if land[p]=="mountain": hills.append(p)
	for good in ["stone","copper","iron","coal"]:
		if hills.is_empty() or sources.any(func(site): return site.good==good): continue
		var i:=rng.randi_range(0,hills.size()-1)
		sources.append({"p":hills[i],"good":good})
		hills.remove_at(i)
	if not sources.any(func(site): return site.good=="grain"):
		for town in towns:
			var field=nearest_kind(town.p,"meadow")
			if field!=null and not sources.any(func(site): return site.p==field):
				sources.append({"p":field,"good":"grain"})
	for p: Vector2i in road_cells:
		node(p)
		for delta in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i(1,1),Vector2i(-1,1)]:
			var other: Vector2i=p+Vector2i(delta)
			if land.get(other) in ["road","bridge"] and (delta.y==0 or delta.x==0 or (land.get(p+Vector2i(delta.x,0))!="river" and land.get(p+Vector2i(0,delta.y))!="river")):
				edge(p,other,true)
	for t in towns:
		var p: Vector2i=t.p
		node(p)
		var nearest=closest(p,road_cells)
		if nearest!=null: trail(p,nearest)
		var others: Array=towns.map(func(v): return v.p)
		others.erase(p)
		for j in mini(others.size(),3 if t.kind=="town" else 1):
			var dest=closest(p,others)
			trail(p,dest)
			others.erase(dest)
		for pair in [["wood","forest"],["water","river"],["grain","grain"]]:
			var target=nearest_kind(p,pair[1])
			if target==null: continue
			if pair[0]=="water":
				var shore: Array=[]
				for delta in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
					var near: Vector2i=target+delta
					if land.has(near) and land[near]!="river": shore.append(near)
				target=closest(p,shore)
			if target!=null and Vector2(p).distance_to(Vector2(target))<=12 and trail(p,target):
				t.sites.append(pair[0])
	for site in sources:
		var owner=closest_town(site.p,false)
		if owner!=null and trail(owner.p,site.p) and not owner.sites.has(site.good): owner.sites.append(site.good)
	for t in towns:
		if t.kind=="village":
			var city=closest_town(t.p,true)
			if city!=null: city.villages.append(t.name)

func closest(p: Vector2i, candidates: Array):
	var best=null
	var dist:=INF
	for q: Vector2i in candidates:
		var d:=p.distance_squared_to(q)
		if d<dist:
			dist=d
			best=q
	return best

func nearest_kind(p: Vector2i,kind: String):
	var options: Array=[]
	for q in land:
		if land[q]==kind: options.append(q)
	return closest(p,options)

func closest_town(p: Vector2i,city_only: bool):
	var choices: Array=[]
	for t in towns:
		if not city_only or t.kind=="town": choices.append(t.p)
	var best=closest(p,choices)
	for t in towns:
		if t.p==best: return t
	return null

func node(p: Vector2i) -> void:
	if not graph.has_point(idx(p)): graph.add_point(idx(p),pos(p))

func edge(p: Vector2i,q: Vector2i,main: bool) -> void:
	node(p)
	node(q)
	if graph.are_points_connected(idx(p),idx(q)): return
	graph.connect_points(idx(p),idx(q))
	segments[Vector2i(mini(idx(p),idx(q)),maxi(idx(p),idx(q)))]=main

func trail(p: Vector2i,q: Vector2i) -> bool:
	var steps:=builder.get_id_path(p,q)
	for i in range(1,steps.size()):
		edge(steps[i-1],steps[i],false)
		builder.set_point_weight_scale(steps[i],0.65)
	return not steps.is_empty()

func route(a: int,b: int,reports: Dictionary, avoid: Array=[]) -> PackedInt64Array:
	if not graph.has_point(a) or not graph.has_point(b): return PackedInt64Array()
	var closed: Array[int]=[]
	for p in bridges:
		if not reports.get(p,{"open":true}).open:
			closed.append(idx(p))
			graph.set_point_disabled(idx(p))
	for id: int in avoid:
		if id!=a and id!=b and graph.has_point(id):
			closed.append(id)
			graph.set_point_disabled(id)
	var path:=graph.get_id_path(a,b)
	for id in closed: graph.set_point_disabled(id,false)
	return path

func height_at(p: Vector2) -> float:
	var base:=Vector2i((p/cell-Vector2(0.5,0.5)).floor())
	var uv: Vector2=(p/cell-Vector2(0.5,0.5))-Vector2(base)
	var h:=0.0
	for y in 2:
		for x in 2:
			var kind: String=land.get(base+Vector2i(x,y),"meadow")
			h+=float({"mountain":95,"forest":7,"river":-3}.get(kind,2))*(uv.x if x else 1-uv.x)*(uv.y if y else 1-uv.y)
	return h

func sees(a: Vector2,b: Vector2,phase: int) -> bool:
	var dist:=a.distance_to(b)
	var radius: float=rules.forest_sight if land.get(Vector2i(a/cell))=="forest" else rules.sight*(1+height_at(a)*rules.gain)
	if land.get(Vector2i(b/cell))=="forest": radius*=float(rules.security.forest_target)
	if dist>radius*float(rules.light[phase]): return false
	var steps:=ceili(dist/12)
	var h1:=height_at(a)+2.0
	var h2:=height_at(b)+2.0
	for j in range(1,steps):
		var t:=float(j)/steps
		var p:=a.lerp(b,t)
		if height_at(p)>lerpf(h1,h2,t): return false
		for tree: Vector2 in obstacles.get(Vector2i(p/cell),[]):
			if p.distance_squared_to(tree)<25: return false
	return true

# When the built roads end, the cart may travel across passable ground.
func ground_route(a: int,b: int,reports: Dictionary,avoid: Array=[]) -> PackedInt64Array:
	var blocked: Array=[]
	for p in bridges:
		if not reports.get(p,{"open":true}).open: blocked.append(p)
	for id: int in avoid:
		if id!=a and id!=b: blocked.append(Vector2i(id%size.x,id/size.x))
	for p in blocked: builder.set_point_solid(p,true)
	var path:=builder.get_id_path(Vector2i(a%size.x,a/size.x),Vector2i(b%size.x,b/size.x))
	for p in blocked: builder.set_point_solid(p,false)
	var ids:=PackedInt64Array()
	for p in path: ids.append(idx(p))
	return ids

func location(id: int) -> Vector2:
	return pos(Vector2i(id%size.x,id/size.x))
