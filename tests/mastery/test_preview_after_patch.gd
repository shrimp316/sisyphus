extends SceneTree
const Preview = preload("res://godot/scenes/mastery/mastery_preview.tscn")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func run() -> void:
	var preview = Preview.instantiate()
	root.add_child(preview)
	await process_frame
	check(preview.screen.node_views.size() == 35, "standalone preview still has35nodes")
	check(preview.adapter.snapshot().mock, "standalone adapter remainsmock")
	for pair in [["zero",0],["250",10],["500",20],["750",30],["first_summit",30],["next_run",35]]:
		preview.screen.apply_fixture(pair[0],false)
		var eligible := 0
		for view in preview.screen.node_views.values(): eligible += int(view.state.eligible)
		check(eligible == pair[1], "old preview fixture distribution " + pair[0])
		preview.screen.select_node("act1_strength_01")
		check(preview.screen.detail_cost.text.contains("강화점 1") and preview.screen.detail_cost.text.contains("EXP 직접 차감 없음"), "standalone does not inherit MVPwallet UI " + pair[0])
		check(preview.screen.detail_effect.text.contains("+2%"), "standalone existingrank effect preserved " + pair[0])
	preview.free()
	await process_frame
	var report := {"checks":checks,"failures":failures,"passed":failures.is_empty(),"scope":"Standalone mock preview defaults after adding MVP-specific hooks; no game save."}
	var file := FileAccess.open("res://tests/mastery/results/v12-patch/verification/preview_smoke.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
