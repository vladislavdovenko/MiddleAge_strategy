extends SceneTree

class County extends "res://region/game.gd":
	func map_file() -> String:
		return "res://tests/fixtures/three_bridges.png"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game:=County.new()
	root.add_child(game)
	game.set_process(false)
	game.rate=game.rates.find(300)
	if not game.ready_map or game.rate<0: quit(1); return
	# Feed the production frame loop 0.1s frames at the selected speed.
	for i in 60: game._process(.1)
	for gate in [Vector2i(41,15),Vector2i(39,33)]:
		if not game.market.toggle(gate): quit(2); return
	var captures:=0
	var patrols:=0
	var deliveries:=game.market.trades
	var bands:Array=game.market.watch.bands
	for window in 8:
		for i in 720:
			var modes:=bands.map(func(b): return b.mode)
			game._process(.1)
			for j in bands.size():
				if modes[j]!="gone" and bands[j].mode=="gone": captures+=1
			for guard in game.market.watch.guards:
				if guard.mode=="patrol": patrols+=1
		print("6h window ",window+1," cargo deliveries ",game.market.trades-deliveries," captures so far ",captures)
		if game.market.trades<=deliveries: quit(3); return
		deliveries=game.market.trades
	if captures==0 or patrols==0 or game.market.time!=174600: quit(4); return
	quit()
