extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game=load("res://region/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if not game.ready_map: quit(1); return
	game.paused=true
	game.cam.position=game.geo.pos(game.geo.towns[2].p)
	game.zoom_level=8
	for i in 45: await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	var result:=image.save_png("res://region-preview.png")
	quit(0 if result==OK else 1)
