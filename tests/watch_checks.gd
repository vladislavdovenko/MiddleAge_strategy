extends SceneTree
const Geo=preload("res://region/geography.gd")
const Market=preload("res://region/market.gd")

func _initialize() -> void:
	var geo:=Geo.new()
	geo.generate(Image.load_from_file("res://tests/fixtures/four_bridges.png"),JSON.parse_string(FileAccess.get_file_as_string("res://region/rules.json")))
	var m:=Market.new()
	m.setup(geo)
	var witness:Dictionary=m.carts[0]
	var dest:int
	for i in geo.towns.size():
		if geo.towns[i].p==Vector2i(29,19): dest=i
	for p in [Vector2i(41,15),Vector2i(39,33)]:
		geo.bridges[p]={"open":false,"version":1}
		m.news(witness,p,geo.bridges[p])
	witness.node=geo.idx(Vector2i(52,16))
	witness.p=geo.location(witness.node)
	witness.dest=dest
	witness.load=9.
	witness.good="wood"
	m.reroute(witness)
	for p in [Vector2i(60,47),Vector2i(15,53)]:
		if not witness.path.has(geo.idx(p)): quit(1); return
	var watch=m.watch
	var guard:Dictionary=watch.guards[0]
	var band:Dictionary=watch.bands[0]
	band.until=999999
	for i in 9000:
		m.advance()
		if witness.at==dest: break
	if witness.at!=dest or witness.trails.is_empty(): quit(2); return
	var other:Dictionary=m.carts[1]
	var near:Vector2=geo.location(witness.node)
	other.p=near
	witness.p=near
	m.advance()
	if other.trails.is_empty(): quit(3); return
	var sighting:int=geo.idx(Vector2i(41,14))
	m.remember(witness,0,sighting,m.time)
	m.share(witness,other,m.time)
	m.remember(other,0,sighting+1,m.time-10)
	if other.memory[0].node!=sighting: quit(4); return
	other.p=guard.p
	watch.tick(m.time-m.time%4+4,1)
	if guard.target!=sighting: quit(5); return
	var forest:Vector2i=geo.nearest_kind(geo.towns[0].p,"forest")
	var inside:Vector2=geo.pos(forest)
	if geo.sees(inside+Vector2(100,0),inside,1): quit(6); return
	band.node=guard.node
	band.p=guard.p
	band.mode="ambush"
	band.until=999999
	watch.tick(m.time-m.time%4+8,1)
	if band.mode!="gone": quit(7); return
	print("PASS four-crossing delivery, route exchange, last sighting, woodland concealment and encounter")
	quit()
