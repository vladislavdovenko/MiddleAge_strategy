extends RefCounted

var geo
var rules: Dictionary
var time := 0
var carts: Array[Dictionary]=[]
var watch:=preload("res://region/watch.gd").new()
var trades := 0
var exchanges := 0

func setup(map) -> void:
	geo=map
	rules=geo.rules
	for i in geo.towns.size():
		var t: Dictionary=geo.towns[i]
		for j in rules.goods.size():
			var good: String=rules.goods.keys()[j]
			var need:=0.0
			for k in rules.classes.size():
				need+=float(t.people[k])*float(rules.needs[rules.classes.keys()[k]][j])/96.0
			t.demand[good]=need
			t.stocks[good]=need*(8 if good in t.sites else 1.2)
		carts.append({"home":i,"at":i,"dest":-1,"p":geo.pos(t.p),"node":geo.idx(t.p),"path":PackedInt64Array(),"next":0,"reports":{},"memory":{},"trails":{},"summoned":{},"aid":false,"good":"","load":0.0,"probe":-1,"scout_cursor":i,"recheck":0,"status":"На ринку"})
	watch.setup(self)
	for cart in carts: dispatch(cart)

func dispatch(cart: Dictionary) -> void:
	var town: Dictionary=geo.towns[cart.at]
	var best:=0.0
	var candidate: Dictionary={}
	var delayed: Dictionary={}
	var delayed_score:=0.0
	for i in geo.towns.size():
		if i==cart.at: continue
		var buyer: Dictionary=geo.towns[i]
		for good in rules.goods:
			var surplus:=float(town.stocks[good])-float(town.demand[good])*2
			var arriving:=0.0
			for other in carts:
				if other.dest==i and other.good==good: arriving+=other.load
			var deficit:=float(buyer.demand[good])*5-float(buyer.stocks[good])-arriving
			var amount:=minf(rules.capacity,minf(surplus,deficit))
			var score:=amount/maxf(1,geo.pos(town.p).distance_to(geo.pos(buyer.p)))
			if score<=best: continue
			var route: PackedInt64Array=journey(cart,geo.idx(buyer.p))
			if route.size()<2:
				if score>delayed_score and not cart.reports.is_empty() and geo.route(cart.node,geo.idx(buyer.p),{}).size()>1:
					delayed_score=score
					delayed={"dest":i,"good":good,"amount":amount,"route":PackedInt64Array()}
				continue
			best=score
			candidate={"dest":i,"good":good,"amount":amount,"route":route}
	if candidate.is_empty(): candidate=delayed
	if candidate.is_empty():
		seek_cargo(cart)
		return
	cart.dest=candidate.dest
	cart.good=candidate.good
	cart.load=candidate.amount
	town.stocks[cart.good]-=cart.load
	cart.path=candidate.route
	cart.next=1
	cart.status="Очікує звісток" if cart.path.is_empty() else "До "+str(geo.towns[cart.dest].name)

# Empty carts can fetch goods at a different market. Discount supply already
# claimed by empty carts heading there and stop reserving it on arrival.
func seek_cargo(cart: Dictionary) -> void:
	var best:=0.0
	var route:=PackedInt64Array()
	var source:=-1
	for i in geo.towns.size():
		if i==cart.at: continue
		var seller:Dictionary=geo.towns[i]
		var claims:=0
		for other in carts:
			if other.dest==i and other.good=="": claims+=1
		var volume:=0.0
		for good in rules.goods:
			var spare:float=seller.stocks[good]-2*seller.demand[good]
			if spare<=0: continue
			var outstanding:=0.0
			for buyer in geo.towns:
				if buyer==seller: continue
				outstanding+=maxf(0,5*buyer.demand[good]-buyer.stocks[good])
			volume+=minf(spare,outstanding)
		var score:=minf(float(rules.capacity),volume-claims*float(rules.capacity))/maxf(1,cart.p.distance_to(geo.pos(seller.p)))
		if score<=best: continue
		var path:=journey(cart,geo.idx(seller.p))
		if path.size()<2: continue
		best=score
		source=i
		route=path
	if source>=0:
		cart.dest=source
		cart.good=""
		cart.load=0.0
		cart.path=route
		cart.next=1
		cart.status="По товар до "+str(geo.towns[source].name)

func economy() -> void:
	for t in geo.towns:
		for good in rules.goods:
			var made:=0.0
			if good in t.sites: made=maxf(float(t.demand[good])*2.5,4.0)
			t.stocks[good]=maxf(0,float(t.stocks[good])+made-float(t.demand[good]))
	for cart in carts:
		if cart.dest<0: dispatch(cart)

func news(cart: Dictionary,p: Vector2i,record: Dictionary) -> void:
	var old: Dictionary=cart.reports.get(p,{"version":-1})
	if old.version>=record.version: return
	cart.reports[p]=record.duplicate()
	if old.get("open",true)!=record.open and cart.dest>=0: reroute(cart)

func reroute(cart: Dictionary) -> void:
	var goal: int=geo.idx(geo.towns[cart.dest].p)
	var path: PackedInt64Array=journey(cart,goal)
	cart.path=path
	cart.next=0
	cart.probe=-1
	cart.aid=false
	cart.status="Об’їзд" if not path.is_empty() else "Очікує звісток"
	cart.recheck=time+150

func scout(cart: Dictionary) -> void:
	# Follow known roads to an approach on this bank; never enter a closed deck.
	var choices: Array=[]
	for bridge in cart.reports:
		if cart.reports[bridge].open: continue
		choices.append(bridge)
	if choices.is_empty(): return
	var cursor: int=cart.get("scout_cursor",cart.home)
	var p: Vector2i=choices[cursor%choices.size()]
	cart.scout_cursor=cursor+1
	for id in geo.graph.get_point_connections(geo.idx(p)):
		var route: PackedInt64Array=geo.route(cart.node,id,cart.reports)
		if route.size()>0:
			cart.path=route
			cart.next=0
			cart.probe=id
			cart.status="Перевіряє переправу"
			break
	cart.recheck=time+150

func journey(cart: Dictionary,goal: int) -> PackedInt64Array:
	var avoid: Array=[]
	for fact in cart.memory.values():
		if time-fact.seen<rules.security.news_life: avoid.append(fact.node)
	# Only the cart's remembered tracks augment the public road network.
	var added: Array=[]
	for edge: Vector2i in cart.trails:
		if not geo.graph.are_points_connected(edge.x,edge.y):
			geo.graph.connect_points(edge.x,edge.y)
			added.append(edge)
	var path: PackedInt64Array=geo.route(cart.node,goal,cart.reports,avoid)
	for edge: Vector2i in added: geo.graph.disconnect_points(edge.x,edge.y)
	if path.is_empty(): path=geo.ground_route(cart.node,goal,cart.reports,avoid)
	return path

func remember(actor: Dictionary,who: int,id: int,seen: int) -> void:
	var old: Dictionary=actor.memory.get(who,{})
	if seen<=old.get("seen",-1): return
	actor.memory[who]={"node":id,"seen":seen}
	if actor.has("dest") and actor.dest>=0 and not actor.aid and actor.path.has(id) and (old.get("node",-1)!=id or time-int(old.get("seen",0))>=rules.security.news_life):
		reroute(actor)

func share(a: Dictionary,b: Dictionary,now: int) -> void:
	for key in a.memory:
		var fact: Dictionary=a.memory[key]
		if now-fact.seen<rules.security.news_life: remember(b,key,fact.node,fact.seen)

func call_guard(cart: Dictionary) -> void:
	if cart.dest<0 or cart.aid: return
	for key in cart.memory:
		var fact: Dictionary=cart.memory[key]
		if time-fact.seen>=rules.security.news_life or time-cart.summoned.get(key,-100000)<rules.security.news_life: continue
		for guard in watch.guards:
			if guard.memory.get(key,{}).get("seen",-1)>=fact.seen and cart.p.distance_to(guard.p)<=rules.contact: continue
			var path: PackedInt64Array=journey(cart,guard.home)
			if path.is_empty(): continue
			cart.path=path
			cart.next=0
			cart.probe=guard.home
			cart.aid=true
			cart.summoned[key]=time
			cart.status="По варту"
			return

func advance() -> void:
	time+=1
	var phase: int=(time/21600)%4
	watch.tick(time,phase)
	for cart in carts:
		for p in geo.bridges:
			var deck: Vector2=geo.pos(p)
			if cart.p.distance_squared_to(deck)<36 or geo.sees(cart.p,deck,phase):
				news(cart,p,geo.bridges[p])
	for i in carts.size():
		for j in range(i):
			var a:=carts[i]
			var b:=carts[j]
			if a.p.distance_to(b.p)>rules.contact or not geo.sees(a.p,b.p,phase): continue
			share(a,b,time)
			share(b,a,time)
			if a.trails.size() or b.trails.size():
				var na:int=a.trails.size()
				var nb:int=b.trails.size()
				a.trails.merge(b.trails)
				b.trails.merge(a.trails)
				if a.trails.size()>na and a.dest>=0 and not a.aid: reroute(a)
				if b.trails.size()>nb and b.dest>=0 and not b.aid: reroute(b)
			for p in geo.bridges:
				if a.reports.has(p) and a.reports[p].version>b.reports.get(p,{"version":-1}).version:
					news(b,p,a.reports[p])
					exchanges+=1
				elif b.reports.has(p) and b.reports[p].version>a.reports.get(p,{"version":-1}).version:
					news(a,p,b.reports[p])
					exchanges+=1
	for cart in carts:
		if cart.dest<0: continue
		if time%12==0: call_guard(cart)
		if cart.path.is_empty():
			if time>=cart.recheck:
				reroute(cart)
				if cart.path.is_empty(): scout(cart)
			continue
		var travel: float=rules.speed
		while travel>0 and cart.next<cart.path.size():
			var id: int=cart.path[cart.next]
			var dest: Vector2=geo.location(id)
			var p:=Vector2i(id%geo.size.x,id/geo.size.x)
			if geo.bridges.has(p) and not geo.bridges[p].open and cart.p.distance_to(dest)<float(rules.contact):
				news(cart,p,geo.bridges[p])
				break
			var distance: float=cart.p.distance_to(dest)
			cart.p=cart.p.move_toward(dest,travel)
			travel-=distance
			if cart.p==dest:
				if cart.node!=id:
					var edge:=Vector2i(mini(cart.node,id),maxi(cart.node,id))
					if not geo.segments.has(edge):
						geo.node(Vector2i(cart.node%geo.size.x,cart.node/geo.size.x))
						geo.node(p)
						cart.trails[edge]=true
					else: watch.traffic[id]=watch.traffic.get(id,0)+1
				cart.node=id
				cart.next+=1
		if not cart.path.is_empty() and cart.next>=cart.path.size():
			cart.path=PackedInt64Array()
			if cart.probe>=0:
				cart.probe=-1
				if cart.aid:
					for guard in watch.guards:
						if cart.p.distance_to(guard.p)<=rules.contact: share(cart,guard,time)
					# Leave a report with the duty watch at its camp.
					for guard in watch.guards:
						if guard.home==cart.node:
							for key in cart.memory:
								var note:Dictionary=cart.memory[key]
								if note.seen>guard.mail.get(key,{}).get("seen",-1): guard.mail[key]=note.duplicate()
					reroute(cart)
				continue
			var t: Dictionary=geo.towns[cart.dest]
			if cart.good!="" and cart.load>0:
				t.stocks[cart.good]+=cart.load
				t.deliveries+=1
				trades+=1
			cart.at=cart.dest
			cart.dest=-1
			cart.load=0.0
			cart.good=""
			cart.status="На ринку"
			dispatch(cart)
	if time%int(rules.period)==0: economy()

func toggle(p: Vector2i) -> bool:
	for c in carts:
		if c.p.distance_to(geo.pos(p))<float(geo.cell)*0.48: return false
	var b: Dictionary=geo.bridges[p]
	b.open=not b.open
	b.version+=1
	return true

func snapshot() -> Dictionary:
	var ledgers: Array=[]
	for town in geo.towns: ledgers.append({"stocks":town.stocks.duplicate(),"deliveries":town.deliveries})
	return {"watch":[watch.bands.duplicate(true),watch.guards.duplicate(true),watch.traffic.duplicate()],"map":geo.fingerprint,"generator":rules.generator,"time":time,"ledgers":ledgers,"gates":geo.bridges.duplicate(true),"carts":carts.duplicate(true),"trades":trades,"exchanges":exchanges}

func valid_node(id: int) -> bool:
	return id>=0 and id<geo.size.x*geo.size.y and geo.land[Vector2i(id%geo.size.x,id/geo.size.x)]!="river"

func restore(data: Variant) -> bool:
	if not data is Dictionary or data.get("map")!=geo.fingerprint or data.get("generator")!=rules.generator: return false
	if not data.get("time") is int or data.time<0 or not data.get("trades") is int or not data.get("exchanges") is int: return false
	if not data.get("ledgers") is Array or data.ledgers.size()!=geo.towns.size(): return false
	if not data.get("carts") is Array or data.carts.size()!=carts.size() or not data.get("gates") is Dictionary: return false
	for row in data.ledgers:
		if not row is Dictionary or not row.get("stocks") is Dictionary or not row.get("deliveries") is int: return false
		for good in rules.goods:
			if typeof(row.stocks.get(good)) not in [TYPE_FLOAT,TYPE_INT] or row.stocks[good]<0: return false
	for c in data.carts:
		if c is Dictionary:
			for k in ["memory","summoned","trails"]:
				if not c.has(k): c[k]={}
			if not c.has("aid"): c.aid=false
		if not c is Dictionary: return false
		for key in carts[0]:
			if not c.has(key): return false
		if not c.p is Vector2 or not c.path is PackedInt64Array or not c.reports is Dictionary: return false
		if c.at<0 or c.at>=geo.towns.size() or c.dest< -1 or c.dest>=geo.towns.size() or (c.node<0 or c.node>=geo.size.x*geo.size.y): return false
		for id in c.path:
			if id<0 or id>=geo.size.x*geo.size.y: return false
	for p in geo.bridges:
		if not data.gates.get(p) is Dictionary or not data.gates[p].get("open") is bool or not data.gates[p].get("version") is int: return false
	for i in geo.towns.size():
		geo.towns[i].stocks=data.ledgers[i].stocks.duplicate()
		geo.towns[i].deliveries=data.ledgers[i].deliveries
	geo.bridges=data.gates.duplicate(true)
	carts.assign(data.carts.duplicate(true))
	for c in carts:
		for e: Vector2i in c.trails:
			for id in [e.x,e.y]: geo.node(Vector2i(id%geo.size.x,id/geo.size.x))
	if data.has("watch"):
		watch.bands.assign(data.watch[0].duplicate(true))
		watch.guards.assign(data.watch[1].duplicate(true))
		watch.traffic=data.watch[2].duplicate()
	time=data.time
	trades=data.trades
	exchanges=data.exchanges
	return true
