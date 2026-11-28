extends SceneTree

const Geo=preload("res://region/geography.gd")
const Market=preload("res://region/market.gd")
var failed:=0

func check(ok: bool,msg: String) -> void:
	if not ok:
		failed+=1
		printerr("FAIL ",msg)

func _initialize() -> void:
	var img:=Image.load_from_file("res://region/world.png")
	var rules: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://region/rules.json"))
	var g:=Geo.new()
	g.generate(img,rules)
	var copy:=Geo.new()
	copy.generate(img,rules)
	check(g.error.is_empty() and g.trees==copy.trees and g.segments==copy.segments and g.towns==copy.towns,"reproducible region")
	img.set_pixel(2,2,Color(rules.palette.village))
	var edited:=Geo.new()
	edited.generate(img,rules)
	check(edited.fingerprint!=g.fingerprint and edited.towns.size()==g.towns.size()+1,"new settlement from PNG")
	var m:=Market.new()
	m.setup(g)
	var keys:=g.bridges.keys()
	check(keys.size()==2,"two crossings")
	var source:int=g.idx(Vector2i(3,15))
	var dest:int=g.idx(Vector2i(75,15))
	check(g.route(source,dest,{}).has(g.idx(keys[0])),"short road crosses north bridge")
	check(g.route(source,dest,{keys[0]:{"open":false}}).has(g.idx(keys[1])),"southern detour")
	check(g.route(source,dest,{keys[0]:{"open":false},keys[1]:{"open":false}}).is_empty(),"both crossings unavailable")
	check(g.route(source,dest,{keys[0]:{"open":true},keys[1]:{"open":false}}).has(g.idx(keys[0])),"north reopens")
	var c:=m.carts[0]
	m.news(c,keys[0],{"open":true,"version":2})
	m.news(c,keys[0],{"open":false,"version":1})
	check(c.reports[keys[0]].open,"ignore stale report")
	for i in 4000: m.advance()
	print("TRADES ",m.trades," TREES ",g.trees.size()," NODES ",g.graph.get_point_count()," REPORTS ",m.exchanges)
	check(m.trades>0,"goods actually delivered")
	for t in g.towns:
		for v in t.stocks.values(): check(v>=0,"inventory nonnegative")
	# An unseen closure stays local; a first-hand report passes at a meeting.
	var remote: Dictionary=m.carts[0]
	var witness: Dictionary=m.carts[1]
	var contact: Dictionary=m.carts[2]
	var gate: Vector2i=keys[0]
	for cart in [remote,witness,contact]:
		cart.dest=-1
		cart.path=PackedInt64Array()
		cart.reports.clear()
	remote.p=Vector2(60,60)
	contact.p=Vector2(65,60)
	witness.p=g.pos(gate)
	g.bridges[gate]={"open":false,"version":7}
	m.advance()
	check(witness.reports[gate].version==7 and not remote.reports.has(gate),"discovery stays local")
	witness.p=Vector2(70,60)
	m.advance()
	check(remote.reports[gate].version==7 and contact.reports[gate].version==7,"news travels at meetings")
	witness.p=g.pos(gate)
	g.bridges[gate]={"open":true,"version":8}
	m.advance()
	check(witness.reports[gate].open and not remote.reports[gate].open,"reopening also needs observation")
	m.news(witness,gate,{"open":false,"version":7})
	check(witness.reports[gate].open,"stale closure cannot override reopening")
	quit(1 if failed else 0)
