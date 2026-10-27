extends SceneTree
const Loader = preload("res://scripts/mastery/mastery_layout_loader.gd")
const Report = preload("res://tests/mastery/test_report.gd")
var report = Report.new()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var nodes: Array = Loader.load_nodes()
	var counts: Dictionary = {"strength": 0, "endurance": 0, "breath": 0, "special": 0}
	var words: Dictionary = {"strength": "", "endurance": "", "breath": ""}
	var expected_words: Dictionary = {"strength": "ΒΙΑΚΑΙΩΣΙΣ", "endurance": "ΜΕΓΑΛΗΡΩΜΗ", "breath": "ΤΑΧΕΙΑΠΝΟΗ"}
	var ids: Dictionary = {}
	var paths: Dictionary = {}
	var ys: Dictionary = {"strength": 434, "endurance": 572, "breath": 708, "special": 856}
	report.check(nodes.size() == 35, "exactly 35 definitions")
	for node: Dictionary in nodes:
		var id: String = node.node_id
		var track: String = node.track
		var index: int = int(node.index)
		report.check(not ids.has(id), "unique id " + id)
		ids[id] = true
		report.check(id == "act1_%s_%02d" % [track, index], "stable logical id " + id)
		report.check(int(node.act) == 1, "act one only " + id)
		counts[track] += 1
		var is_special: bool = track == "special"
		var x: int = 555 + 147 * (index - 1) if is_special else 425 + 96 * (index - 1)
		report.check(int(node.x) == x and int(node.y) == int(ys[track]), "authoritative CSV center " + id)
		if is_special:
			report.check(int(node.milestone_m) == 1000, "special summit requirement unchanged " + id)
			report.check(str(node.greek_letter).is_empty() and str(node.greek_codepoint).is_empty(), "special has no inscription " + id)
			for state: String in ["engraved", "ready", "active"]:
				report.check(str(node["glyph_%s_png" % state]).is_empty(), "special has no " + state + " glyph " + id)
			report.check(str(node.icon_asset).ends_with("special_placeholder_%02d.png" % index), "special retains supplied placeholder " + id)
		else:
			var first_count: int = 4 if track == "strength" else 3
			var second_count: int = 6 if track == "breath" else 7
			var expected_milestone: int = 150 if index <= first_count else (400 if index <= second_count else 700)
			report.check(int(node.milestone_m) == expected_milestone, "updated 150/400/700 tier mapping " + id)
			var letter: String = str(node.greek_letter)
			words[track] += letter
			report.check(letter.length() == 1 and letter == str(expected_words[track])[index - 1], "indexed core letter " + id)
			report.check(str(node.greek_codepoint) == "%04X" % letter.unicode_at(0), "Unicode mapping " + id)
			for state: String in ["engraved", "ready", "active"]:
				var path: String = Loader.asset_path(str(node["glyph_%s_png" % state]))
				report.check(path.ends_with("glyphs/%s/%s.png" % [state, node.greek_codepoint]), "state-specific glyph path " + id + " " + state)
				report.check(ResourceLoader.exists(path), "imported glyph exists " + id + " " + state)
				var texture = load(path)
				report.check(texture is Texture2D and texture.get_size() == Vector2(128, 128), "glyph texture dimensions " + id + " " + state)
				if paths.has(path):
					report.check(texture == paths[path], "shared glyph ResourceLoader cache " + path)
				paths[path] = texture
	report.check(counts == {"strength": 10, "endurance": 10, "breath": 10, "special": 5}, "10/10/10/5 counts")
	report.check(words == expected_words, "three complete original inscriptions")
	var bank: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mastery/mastery_greek_inscriptions_v12.json"))
	report.check(bank.inscriptions.size() == 4, "four original act inscriptions preserved")
	for act: String in bank.inscriptions:
		for track: String in ["strength", "endurance", "breath"]:
			var item: Dictionary = bank.inscriptions[act][track]
			var core: String = item.coreText
			report.check(core.length() == 10, "ten-letter core act %s %s" % [act, track])
			report.check(item.has("extensionText_legacy_unassigned"), "legacy extension marked unassigned act %s %s" % [act, track])
			for letter: String in core:
				for state: String in ["engraved", "ready", "active"]:
					report.check(ResourceLoader.exists("res://assets/ui/mastery/inscriptions/glyphs/%s/%04X.png" % [state, letter.unicode_at(0)]), "future core glyph supplied act %s %s %s %s" % [act, track, letter, state])
	var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mastery/mastery_act_schema_v12.json"))
	report.check(schema.total_reserved_slots == 140 and schema.maximum_visible_nodes == 35, "140 reserved slots but maximum35 visible")
	var expected_counts: Dictionary = {"strength":10,"endurance":10,"breath":10,"special":5}
	for track: String in expected_counts:
		report.check(int(schema.nodes_per_act.get(track, -1)) == expected_counts[track], "future act component count " + track)
	for act: Dictionary in schema.acts:
		if int(act.act) == 1:
			var thresholds: Array = act.normal_unlock_milestones
			report.check(thresholds.size() == 3 and int(thresholds[0]) == 150 and int(thresholds[1]) == 400 and int(thresholds[2]) == 700, "act one schema records new unlock thresholds")
			continue
		report.check(not act.implemented and act.layout == null and act.effects == null and act.costs == null and act.gates == null, "future act rules remain undefined " + str(act.act))
	quit(report.finish("data_validation", {"nodes": nodes.size(), "counts": counts, "inscriptions": words, "scope": "Godot CSV loader, imported PNGs, 90 normal node-state mappings and 12 preserved act-track cores"}))
