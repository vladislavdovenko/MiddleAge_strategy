extends Node2D

var origin := Vector2.ZERO
var radius := 0.0
var limits := Rect2()
var sight
var rim := PackedVector2Array()

func update_view(p: Vector2,phase: int,model) -> void:
	sight = model
	origin = p
	radius = sight.radius(p,phase)
	limits = sight.terrain.bounds
	rim.clear()
	for i in 96:
		var direction := Vector2.RIGHT.rotated(TAU*i/96.0)
		var distance := radius
		# Ground visibility can resume beyond a ridge. The silhouette represents
		# foreground cover; each entity also has an independent line-of-sight test.
		for j in range(1,17):
			var d := radius*j/16.0
			if not sight.clear_line(p,p+direction*d):
				distance = radius*(j-1)/16.0
				break
		rim.append(p+direction*distance)
	queue_redraw()

func _draw() -> void:
	var extent := limits.size.length()*2
	var fog := Color(0.16,0.19,0.23,0.38)
	for i in rim.size():
		var a := Vector2.RIGHT.rotated(TAU*i/rim.size())
		var b := Vector2.RIGHT.rotated(TAU*(i+1)/rim.size())
		draw_colored_polygon(PackedVector2Array([rim[i],origin+a*extent,origin+b*extent,rim[(i+1)%rim.size()]]),fog)
