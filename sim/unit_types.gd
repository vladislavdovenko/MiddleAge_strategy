extends RefCounted

static func load_speeds(path: String = "res://data/unit_types.tsv") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_csv_line("\t") != PackedStringArray(["type_id", "speed_mps"]):
		push_error("Cannot read unit_types header: " + path)
		return {}
	var speeds := {}
	while file.get_position() < file.get_length():
		var row := file.get_csv_line("\t")
		if row.size() != 2 or row[0].is_empty() or speeds.has(row[0]) or not row[1].is_valid_float():
			push_error("Invalid or duplicate unit type: " + str(row))
			return {}
		var speed := row[1].to_float()
		if not is_finite(speed) or speed <= 0.0:
			push_error("Invalid speed: " + row[1])
			return {}
		speeds[row[0]] = speed
	return speeds
