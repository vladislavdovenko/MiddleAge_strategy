extends RefCounted

var rules: Dictionary
var terrain
var obstacles: Array = []

func setup(config: Dictionary, geography) -> void:
	rules = config
	terrain = geography

func height(p: Vector2) -> float:
	var h := 0.0
	for hill in rules.hills:
		var d := (p-Vector2(hill[0],hill[1]))/Vector2(hill[2],hill[3])
		h += float(hill[4])*exp(-d.length_squared()*2.0)
	return h

func in_forest(p: Vector2) -> bool:
	for zone in terrain.data.zones:
		if zone.kind in ["forest","mountain_forest"] and terrain.zone_rect(zone).has_point(p): return true
	return false

func radius(p: Vector2, phase: int) -> float:
	var daylight: float = rules.phases[phase].range
	if in_forest(p): return rules.forest*daylight
	return rules.range*(1.0+height(p)*rules.height_gain)*daylight

func rebuild_objects(sprites: Dictionary) -> void:
	obstacles.clear()
	for sprite: Sprite2D in sprites.values():
		var asset: String = sprite.get_meta("asset")
		if rules.blockers.has(asset):
			var dims: Array = rules.blockers[asset]
			obstacles.append([sprite.position,float(dims[0])*sprite.scale.x,float(dims[1])*sprite.scale.y])

func clear_line(a: Vector2,b: Vector2) -> bool:
	var dist := a.distance_to(b)
	if dist<1: return true
	var start := height(a)+float(rules.eye)
	var end := height(b)+float(rules.target)
	var samples := ceili(dist/float(rules.step))
	var woods := 0.0
	for i in range(1,samples):
		var t := float(i)/samples
		var p := a.lerp(b,t)
		if height(p)>lerpf(start,end,t): return false
		if in_forest(p):
			woods += dist/samples
			if woods>float(rules.forest): return false
	for ob in obstacles:
		var base: Vector2 = ob[0]
		var t := (base-a).dot(b-a)/(dist*dist)
		if t<=0 or t>=1 or base.distance_to(b)<=ob[1]: continue
		if base.distance_to(a.lerp(b,t))<=ob[1] and height(base)+float(ob[2])>lerpf(start,end,t): return false
	return true

func sees(a: Vector2,b: Vector2,phase: int) -> bool:
	return a.distance_to(b)<=radius(a,phase) and clear_line(a,b)
