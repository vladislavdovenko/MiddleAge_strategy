extends RefCounted

var market
var geo
var cfg: Dictionary
var camps: Array[Dictionary]=[]
var bands: Array[Dictionary]=[]
var guards: Array[Dictionary]=[]
var traffic: Dictionary={}

func setup(m) -> void:
	market=weakref(m)
	geo=m.geo
	cfg=geo.rules.security
	for kind in ["garrison","outlaws"]:
		var positions: Array=[]
		for p in geo.land:
			if geo.land[p]==kind: positions.append(p)
		if positions.is_empty():
			var fallback=geo.towns[0].p if kind=="garrison" else geo.nearest_kind(geo.towns[0].p,"forest")
			if fallback!=null: positions.append(fallback)
		for p: Vector2i in positions:
			var id:int=geo.idx(p)
			camps.append({"kind":kind,"p":p})
			var actor={"home":id,"node":id,"p":geo.pos(p),"path":PackedInt64Array(),"step":0,"mode":"camp","until":int(cfg.leave_after),"memory":{},"handled":{},"mail":{},"target":-1,"cover":-1}
			if kind=="garrison": guards.append(actor)
			else: bands.append(actor)

func travel(actor: Dictionary,id: int,mode: String) -> bool:
	if id<0: return false
	var path: PackedInt64Array=geo.ground_route(actor.node,id,closed_bridges())
	if path.is_empty(): return false
	actor.path=path
	actor.step=0
	if path.size()>1:
		var start:Vector2=geo.location(path[0])
		var next:Vector2=geo.location(path[1])
		if Geometry2D.get_closest_point_to_segment(actor.p,start,next).distance_to(actor.p)<0.1: actor.step=1
	actor.mode=mode
	return true

func closed_bridges() -> Dictionary:
	# Physical crossing constraint for patrols and outlaws.
	return geo.bridges

func move(actor: Dictionary,speed: float) -> void:
	var remaining:=speed
	while remaining>0 and actor.step<actor.path.size():
		var id:int=actor.path[actor.step]
		var cell:=Vector2i(id%geo.size.x,id/geo.size.x)
		if geo.bridges.has(cell) and not geo.bridges[cell].open:
			if not travel(actor,actor.path[-1],actor.mode):
				actor.path=PackedInt64Array()
				actor.mode="stranded"
			return
		var to:Vector2=geo.location(id)
		var dist:float=to.distance_to(actor.p)
		actor.p=actor.p.move_toward(to,remaining)
		remaining-=dist
		if actor.p==to:
			actor.node=id
			actor.step+=1

func choose_road(b: Dictionary) -> bool:
	var score:=-1.0
	var target:=-1
	var cover:=-1
	for id: int in traffic:
		var p:=Vector2i(id%geo.size.x,id/geo.size.x)
		if geo.bridges.has(p) or not geo.graph.has_point(id): continue
		var distance:float=geo.location(b.home).distance_to(geo.location(id))
		var value:float=float(traffic[id])/(1+distance/400)
		if value<=score: continue
		var nearby: Array=[]
		for y in range(-6,7):
			for x in range(-6,7):
				var near:=p+Vector2i(x,y)
				if geo.forests.has(near): nearby.append(near)
		var tree=geo.closest(p,nearby)
		if tree==null or tree.distance_squared_to(p)>36: continue
		if geo.ground_route(b.node,geo.idx(tree),closed_bridges()).is_empty() or geo.ground_route(geo.idx(tree),id,closed_bridges()).is_empty(): continue
		score=value
		target=id
		cover=geo.idx(tree)
	if target<0: return false
	b.target=target
	b.cover=cover
	return travel(b,cover,"woods")

func patrol(guard: Dictionary,now: int) -> void:
	var towns:Array=geo.towns.duplicate()
	var home:Vector2=geo.location(guard.home)
	towns.sort_custom(func(a,b): return home.distance_squared_to(geo.pos(a.p))<home.distance_squared_to(geo.pos(b.p)))
	var count:=mini(3,towns.size())
	var cursor:int=guard.get("patrol_cursor",0)
	for offset in count:
		var index: int=(cursor+offset)%count
		var id:int=geo.idx(towns[index].p)
		if id!=guard.node and travel(guard,id,"patrol"):
			guard.patrol_cursor=index+1
			return
	guard.until=now+120

func tick(now: int,phase: int) -> void:
	var m=market.get_ref()
	for b in bands:
		match b.mode:
			"camp","gone":
				if now>=b.until:
					if b.mode=="gone": b.p=geo.location(b.home); b.node=b.home
					b.mode="camp"
					b.until=now+cfg.leave_after
					choose_road(b)
			"ambush":
				if now>=b.until: travel(b,b.cover,"escape")
			"hidden":
				if now>=b.until: travel(b,b.home,"return")
			"stranded":
				if now%60==0: travel(b,b.home,"return")
		if b.mode=="gone": continue
		move(b,cfg.bandit_speed)
		if b.step>=b.path.size():
			match b.mode:
				"woods": travel(b,b.target,"approach")
				"approach": b.mode="ambush"; b.until=now+cfg.ambush_time
				"escape": b.mode="hidden"; b.until=now+cfg.rest_time
				"return": b.mode="camp"; b.until=now+cfg.rest_time
	for guard in guards:
		move(guard,cfg.guard_speed)
		if guard.step>=guard.path.size():
			match guard.mode:
				"investigate": guard.mode="search"; guard.until=now+90
				"search":
					if now>=guard.until: travel(guard,guard.home,"return")
				"patrol":
					if not travel(guard,guard.home,"return"): guard.mode="stranded"
				"return": guard.mode="camp"; guard.target=-1; guard.until=now+90
				"stranded":
					if now%60==0: travel(guard,guard.home,"return")
		if guard.mode=="camp":
			for key in guard.mail:
				var record:Dictionary=guard.mail[key]
				m.remember(guard,key,record.node,record.seen)
			guard.mail.clear()
			if now>=guard.until: patrol(guard,now)
	if now%4!=0: return
	for i in bands.size():
		var b:=bands[i]
		if b.mode not in ["approach","ambush","escape","hidden"]: continue
		for cart in m.carts:
			if geo.sees(cart.p,b.p,phase):
				m.remember(cart,i,b.node,now)
				if b.mode=="ambush" and b.p.distance_to(cart.p)<=cfg.encounter and cart.load>0:
					cart.load*=1.0-float(cfg.robbed_fraction)
					travel(b,b.cover,"escape")
		for guard in guards:
			if geo.sees(guard.p,b.p,phase):
				m.remember(guard,i,b.node,now)
				guard.handled[i]=now
				if guard.p.distance_to(b.p)<=cfg.encounter:
					b.mode="gone"
					b.path=PackedInt64Array()
					b.until=now+cfg.rest_time
					break
				if guard.target!=b.node or guard.mode!="investigate":
					if travel(guard,b.node,"investigate"): guard.target=b.node
			if b.mode in ["approach","ambush"] and geo.sees(b.p,guard.p,phase): travel(b,b.cover,"escape")
	for guard in guards:
		for cart in m.carts:
			if guard.p.distance_to(cart.p)<=geo.rules.contact and geo.sees(guard.p,cart.p,phase):
				m.share(cart,guard,now)
				m.share(guard,cart,now)
		var newest:=-1
		var spot:=-1
		var who:=-1
		for key in guard.memory:
			var fact:Dictionary=guard.memory[key]
			if now-fact.seen>=cfg.news_life or fact.seen<=guard.handled.get(key,-1): continue
			if fact.seen>newest:
				newest=fact.seen
				spot=fact.node
				who=key
		if spot>=0 and ((guard.mode=="investigate" and guard.target==spot) or travel(guard,spot,"investigate")):
			guard.handled[who]=newest
			guard.target=spot
	if now%900==0:
		for id in traffic.keys():
			traffic[id]=int(traffic[id])/2
			if traffic[id]==0: traffic.erase(id)
