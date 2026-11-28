extends RefCounted

const World = preload("res://sim/world.gd")
const Sight = preload("res://sim/sight.gd")
var world
var map
var config: Dictionary
var sight := Sight.new()
var knowledge := {}
var pending := {}
var live := {}
var navigators := {}
var reports := {}
var locations := {}
var revision := 0

func setup(sim,geography,definition: Dictionary) -> void:
	world = sim
	map = geography
	config = definition
	sight.setup(config.sight,map)
	for actor in config.actors:
		world.add_group(actor.id,Vector2(actor.pos[0],actor.pos[1]),actor.speed)
		navigators[actor.id] = preload("res://map/valley.gd").new()
		reports[actor.id] = {}
	for site in config.sites: locations[site.id] = Vector2(site.pos[0],site.pos[1])
	for id in map.crossings: locations[id] = map.crossings[id].get_center()

func observe() -> void:
	var origin: Vector2 = world.groups[config.lord].position
	live.clear()
	for id in locations:
		if sight.sees(origin,locations[id],world.phase()):
			live[id] = true
			knowledge[id] = {"time":world.time_seconds,"state":map.gates.get(id,true)}
	for id in world.groups:
		var p: Vector2 = world.groups[id].position
		if id==config.lord or sight.sees(origin,p,world.phase()):
			live[id] = true
			knowledge[id] = {"time":world.time_seconds,"position":p}

func send_to(id: String,destination: Vector2) -> bool:
	var g: World.Group = world.groups[id]
	var navigator = navigators[id]
	navigator.data.zones = map.data.zones
	for crossing in map.crossings:
		var believed: bool = reports[id].get(crossing,true)
		if navigator.gates[crossing]!=believed: navigator.set_gate(crossing,believed)
	var route: Dictionary = navigator.route(g.position,destination,g.speed_mps)
	if route.is_empty(): return false
	var success: bool = world.follow_route(id,route.points,route.times)
	if success and id==config.lord and pending.is_empty():
		var follower: World.Group = world.groups[config.courier]
		if follower.position.distance_to(g.position)<=config.message_range: send_to(config.courier,destination)
	return success

func issue_cart(destination: Vector2) -> bool:
	var lord: Vector2 = world.groups[config.lord].position
	var cart: Vector2 = world.groups[config.cart].position
	if lord.distance_to(cart)<=config.message_range and live.has(config.cart):
		if not send_to(config.cart,destination): return false
		pending.clear()
		return true
	var messenger: World.Group = world.groups[config.courier]
	if messenger.position.distance_to(lord)>config.message_range: return false
	if not knowledge.has(config.cart): return false
	if not send_to(config.courier,knowledge[config.cart].position): return false
	pending = {"target":destination,"stage":"out"}
	return true

func update_routes() -> void:
	for id in world.groups:
		var g: World.Group = world.groups[id]
		var changed := false
		for gate in map.crossings:
			var deck: Rect2 = map.crossings[gate]
			var nearest := g.position.clamp(deck.position,deck.end)
			if g.position.distance_to(nearest)>g.speed_mps+2 and not sight.sees(g.position,deck.get_center(),world.phase()): continue
			if reports[id].get(gate,true)!=map.gates[gate]: changed = true
			reports[id][gate] = map.gates[gate]
		if changed and g.moving and not send_to(id,g.target): g.moving = false

func invalidate_terrain() -> void:
	for nav in navigators.values(): nav.graph = null

func advance(seconds: int) -> void:
	for i in seconds:
		update_routes()
		world.advance(1)
		for change in config.get("events",[]):
			if world.time_seconds==change.time and map.gates[change.gate]!=change.open: toggle_gate(change.gate)
		observe()
		if pending.is_empty(): continue
		var messenger: World.Group = world.groups[config.courier]
		var cart: World.Group = world.groups[config.cart]
		var lord: World.Group = world.groups[config.lord]
		if pending.stage=="out":
			if messenger.position.distance_to(cart.position)<=config.message_range:
				pending.delivered = send_to(config.cart,pending.target)
				pending.stage = "return"
				send_to(config.courier,lord.position)
			elif not messenger.moving and sight.sees(messenger.position,cart.position,world.phase()):
				send_to(config.courier,cart.position)
		elif messenger.position.distance_to(lord.position)<=config.message_range:
			pending.clear()
		elif not messenger.moving: send_to(config.courier,lord.position)

func toggle_gate(id: String) -> bool:
	if not map.gates.has(id): return false
	for g in world.groups.values():
		if map.gates[id] and map.crossings[id].has_point(g.position): return false
	map.set_gate(id,not map.gates[id])
	update_routes()
	observe()
	revision += 1
	return true

func snapshot() -> Dictionary:
	var groups := {}
	for id in world.groups:
		var row := {}
		for key in ["position","origin","target","path","times","departed_at","due_at","order","moving"]:
			row[key] = world.groups[id].get(key)
		groups[id] = row
	return {"version":1,"groups":groups,"time":world.time_seconds,"sequence":world._next_order,"arrivals":world.arrivals.duplicate(true),"gates":map.gates.duplicate(),"memory":knowledge.duplicate(true),"message":pending.duplicate(true),"reports":reports.duplicate(true)}

func restore(s: Variant) -> bool:
	if not s is Dictionary or s.get("version")!=1: return false
	for key in ["groups","gates","memory","message"]:
		if not s.get(key) is Dictionary: return false
	if not s.get("time") is int or not s.get("sequence") is int or not s.get("arrivals") is Array: return false
	for id in world.groups:
		if not s.groups.get(id) is Dictionary: return false
		var row: Dictionary = s.groups[id]
		if not row.get("position") is Vector2 or not row.get("path") is PackedVector2Array or not row.get("times") is PackedFloat64Array: return false
		if row.path.size()!=row.times.size(): return false
		for key in ["origin","target","order","moving","due_at","departed_at"]:
			if not row.has(key): return false
	for id in map.gates:
		if not s.gates.get(id) is bool: return false
	for id in world.groups:
		var g: World.Group = world.groups[id]
		for key in ["position","origin","target","path","times","departed_at","due_at","order","moving"]: g.set(key,s.groups[id][key])
	world.time_seconds = s.time
	world._next_order = s.sequence
	world.arrivals.assign(s.arrivals)
	for id in map.gates: map.set_gate(id,s.gates[id])
	knowledge = s.memory.duplicate(true)
	pending = s.message.duplicate(true)
	for id in reports: reports[id] = s.get("reports",{}).get(id,{}).duplicate(true)
	observe()
	revision += 1
	return true
