extends SceneTree
const Scene = preload("res://scenes/mvp/main_mvp.tscn")
const Contract = preload("res://scripts/mvp/save_contract.gd")
const SOURCE := "res://tests/mvp/fixtures/web/milestone250.json"
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var original_hash := FileAccess.get_sha256(SOURCE)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	check(int(data.modal_milestone.distance)==250 and int(data.mastery.available_exp)==150,"checked-in legacy 250m / 150EXP")
	check(Contract.validate(data),"legacy envelope accepted")
	var path := "res://.tools/unlock-host-review-%d.json" % Time.get_ticks_usec()
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var main = Scene.instantiate()
	main.save_path = path
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	await process_frame
	check(main.save_path==path and main.has_resume and not main.save_blocked,"actual host restored isolated save")
	check(int(main.modal_milestone.distance)==150,"actual host normalized old modal")
	check(main.mastery.available_exp==150,"actual host preserved EXP")
	main._menu_action("continue")
	await process_frame
	check(main.ui_mode=="board" and main.board.visible and main.paused,"continue reopens pending modal")
	check(main.board.act_label.text.begins_with("150m"),"visible heading 150m")
	check(main.board.exp_label.text=="150 EXP","visible wallet 150EXP")
	check(main.board.purchase_allowed,"old modal keeps purchase opportunity")
	main.board.skip_animations()
	main._close_board()
	await process_frame
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(Contract.validate(saved),"host saved migrated state contract")
	check(saved.modal_milestone.is_empty() and saved.mastery.available_exp==150,"close clears modal without charging EXP")
	check(not main.persistence_failed and not main.save_blocked,"no save block")
	check(FileAccess.get_sha256(SOURCE)==original_hash,"original fixture unchanged")
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var output := FileAccess.open("res://tests/mastery/results/unlock-150-400-700/legacy_host.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"source":SOURCE,"source_sha256":original_hash,"scope":"actual scene host load/continue/close/save calls in headless; no browser or new visual capture"},"\t"))
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
