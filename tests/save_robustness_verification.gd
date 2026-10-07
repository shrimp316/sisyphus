extends SceneTree

var failures: int = 0
var checks: int = 0
const SAVE_PATH: String = "res://.tools/qa-invalid-save.json"

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1

func run() -> void:
	var invalid_data: Array[String] = ["{broken json", JSON.stringify({"version": 99, "run": {}}), JSON.stringify({"version": 2, "world": {}, "run": {}}), JSON.stringify({"version": 1})]
	for index in range(invalid_data.size()):
		var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		file.store_string(invalid_data[index])
		file.close()
		var app: Node2D = load("res://main.tscn").instantiate()
		root.add_child(app)
		app.set_physics_process(false)
		check(app.save_blocked and not app.has_resume and not app.save_error.is_empty(), "invalid save case%d is rejected with visible explanation" % index)
		app._begin()
		check(app.screen == "title" and FileAccess.get_file_as_string(SAVE_PATH) == invalid_data[index], "invalid save case%d cannot silently start or overwrite" % index)
		app.queue_free()
		await process_frame
	var app: Node2D = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_physics_process(false)
	app.save_blocked = false
	app.save_path = "res://.tools/qa-missing-parent/save.json"
	app.screen = "game"
	app._save_and_quit()
	check(app.paused and not app.quitting and not app.save_error.is_empty(), "failed save keeps session paused with retryable error")
	check(not app.sound.shutting_down, "failed save preserves audio/session for retry")
	app.queue_free()
	await process_frame
	print("SAVE ROBUSTNESS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
