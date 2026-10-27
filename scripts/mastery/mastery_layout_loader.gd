extends RefCounted
## CSV remains the authority; no generated coordinates or invented future-act rules.
const PATH := "res://data/mastery/mastery_node_layout_v12.csv"

static func asset_path(path: String) -> String:
	if path.is_empty(): return ""
	if path.begins_with("res://"): return path
	if path.begins_with("assets/"): return "res://" + path
	return "res://assets/ui/mastery/" + path

static func load_nodes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("Mastery mapping is missing: " + PATH)
		return result
	var headers := file.get_csv_line()
	if not headers.is_empty(): headers[0] = headers[0].trim_prefix("\ufeff")
	while not file.eof_reached():
		var values := file.get_csv_line()
		if values.size() != headers.size(): continue
		var row: Dictionary = {}
		for i in headers.size(): row[headers[i]] = values[i]
		for field in ["act", "index", "milestone_m", "x", "y"]: row[field] = int(row[field])
		row["is_placeholder"] = str(row["is_placeholder"]) == "true"
		result.append(row)
	return result
