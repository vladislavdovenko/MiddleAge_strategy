extends RefCounted

var geo
var rules: Dictionary
var time := 0
var carts: Array[Dictionary]=[]
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
		carts.append({"home":i,"at":i,"dest":-1,"p":geo.pos(t.p),"node":geo.idx(t.p),"path":PackedInt64Array(),"next":0,"reports":{},"good":"","load":0.0,"probe":-1,"scout_cursor":i,"recheck":0,"status":"На ринку"})
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
			var route: PackedInt64Array=geo.route(cart.node,geo.idx(buyer.p),cart.reports)
			if route.size()<2:
				if score>delayed_score and not cart.reports.is_empty() and geo.route(cart.node,geo.idx(buyer.p),{}).size()>1:
					delayed_score=score
					delayed={"dest":i,"good":good,"amount":amount,"route":PackedInt64Array()}
				continue
			best=score
			candidate={"dest":i,"good":good,"amount":amount,"route":route}
	if candidate.is_empty(): candidate=delayed
	if candidate.is_empty(): return
	cart.dest=candidate.dest
	cart.good=candidate.good
	cart.load=candidate.amount
	town.stocks[cart.good]-=cart.load
	cart.path=candidate.route
	cart.next=1
	cart.status="Очікує звісток" if cart.path.is_empty() else "До "+str(geo.towns[cart.dest].name)

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
	var path: PackedInt64Array=geo.route(cart.node,goal,cart.reports)
	cart.path=path
	cart.next=0
	cart.probe=-1
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

func advance() -> void:
	time+=1
	var phase: int=(time/21600)%4
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
			for p in geo.bridges:
				if a.reports.has(p) and a.reports[p].version>b.reports.get(p,{"version":-1}).version:
					news(b,p,a.reports[p])
					exchanges+=1
				elif b.reports.has(p) and b.reports[p].version>a.reports.get(p,{"version":-1}).version:
					news(a,p,b.reports[p])
					exchanges+=1
	for cart in carts:
		if cart.dest<0: continue
		if cart.path.is_empty():
			if time>=cart.recheck: scout(cart)
			continue
		var travel: float=rules.speed
		while travel>0 and cart.next<cart.path.size():
			var id: int=cart.path[cart.next]
			var dest: Vector2=geo.graph.get_point_position(id)
			var p:=Vector2i(id%geo.size.x,id/geo.size.x)
			if geo.bridges.has(p) and not geo.bridges[p].open and cart.p.distance_to(dest)<float(rules.contact):
				news(cart,p,geo.bridges[p])
				break
			var distance: float=cart.p.distance_to(dest)
			cart.p=cart.p.move_toward(dest,travel)
			travel-=distance
			if cart.p==dest:
				cart.node=id
				cart.next+=1
		if not cart.path.is_empty() and cart.next>=cart.path.size():
			cart.path=PackedInt64Array()
			if cart.probe>=0:
				cart.probe=-1
				continue
			var t: Dictionary=geo.towns[cart.dest]
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
	return {"map":geo.fingerprint,"generator":rules.generator,"time":time,"ledgers":ledgers,"gates":geo.bridges.duplicate(true),"carts":carts.duplicate(true),"trades":trades,"exchanges":exchanges}

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
		if not c is Dictionary: return false
		for key in carts[0]:
			if not c.has(key): return false
		if not c.p is Vector2 or not c.path is PackedInt64Array or not c.reports is Dictionary: return false
		if c.at<0 or c.at>=geo.towns.size() or c.dest< -1 or c.dest>=geo.towns.size() or not geo.graph.has_point(c.node): return false
		for id in c.path:
			if not geo.graph.has_point(id): return false
	for p in geo.bridges:
		if not data.gates.get(p) is Dictionary or not data.gates[p].get("open") is bool or not data.gates[p].get("version") is int: return false
	for i in geo.towns.size():
		geo.towns[i].stocks=data.ledgers[i].stocks.duplicate()
		geo.towns[i].deliveries=data.ledgers[i].deliveries
	geo.bridges=data.gates.duplicate(true)
	carts.assign(data.carts.duplicate(true))
	time=data.time
	trades=data.trades
	exchanges=data.exchanges
	return true
