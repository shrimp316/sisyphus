extends SceneTree

var failures: int = 0
var checks: int = 0
var app: Node2D
const SAVE_PATH: String = "res://.tools/qa-migration-save.json"
const EXPECTED_PATH: String = "res://.tools/qa-migration-expected.json"

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1

func write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func run() -> void:
	var resume_check: bool = "--migration-resume" in OS.get_cmdline_user_args()
	if not resume_check:
		write_json(SAVE_PATH, {"version": 1, "best": 472.0, "run_number": 4, "falls_seen": 1, "run": {"distance": 421.25, "velocity": -0.75, "stamina": 27.5, "slip": 36.0, "slip_remaining": 0.25, "peak": 451.0, "elapsed": 112.5, "state": "climbing", "slips": 2}})
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_physics_process(false)
	if resume_check:
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED_PATH))
		check(app.has_resume and app.run_number == 5 and app.best == 472.0 and app.falls_seen == 1, "v2 restore preserves migrated persistent statistics")
		check(JSON.parse_string(JSON.stringify(app.mountain.snapshot())) == expected.world, "v2 restores exact generated world despite different seed/weather launch flags")
		check(JSON.parse_string(JSON.stringify(app.boulder.snapshot())) == expected.run, "v2 restores exact run state across engine processes")
		print("MIGRATION RESUME: %d checks, %d failures" % [checks, failures])
		quit(1 if failures else 0)
		return
	check(app.has_resume and app.boulder.distance == 421.25 and app.boulder.velocity == -0.75 and app.boulder.stamina == 27.5, "v1 existing run resumes without relocation")
	var legacy := MountainManager.new(1, true)
	check(app.mountain.segments == legacy.segments, "v1 migration preserves original 20 fixed climbs and shelf geometry")
	var control := BoulderController.new(legacy)
	control.restore(app.boulder.snapshot())
	for i in range(120):
		app.boulder.advance(1.0 / 120.0, true, true, false)
		control.advance(1.0 / 120.0, true, true, false)
	check(app.boulder.snapshot() == control.snapshot(), "v1 migrated run retains legacy physics response")
	app._new_run()
	app.set_physics_process(false)
	check(app.run_number == 5 and app.boulder.distance == 0.0 and app.boulder.stamina == 100.0, "new run after v1 migration resets only run state")
	check(app.mountain.segments != legacy.segments, "next run after v1 migration uses new chunk world")
	check(app.path.curve == app.mountain.curve and app.boulder.mountain == app.mountain, "new run synchronizes render curve and physics world")
	app.boulder.distance = 62.25
	app.boulder.peak = 83.75
	app.boulder.stamina = 43.25
	app.boulder.velocity = 1.125
	app.boulder.slip = 55.5
	app.boulder.elapsed = 42.5
	app.camera_position = app.mountain.sample(62.25)
	write_json(EXPECTED_PATH, {"world": app.mountain.snapshot(), "run": app.boulder.snapshot()})
	print("MIGRATION WRITE: %d checks, %d failures" % [checks, failures])
	if failures:
		quit(1)
	else:
		app._save_and_quit()

