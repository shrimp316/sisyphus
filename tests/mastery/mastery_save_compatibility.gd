extends SceneTree
## Real legacy v4 round trip in a fresh test-only directory, never user://.
const Main = preload("res://scripts/main.gd")
const Growth = preload("res://scripts/progression.gd")
const Report = preload("res://tests/mastery/test_report.gd")
var report = Report.new()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var fixture: String = "res://.tools/mastery-v12-save-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	var app = Main.new()
	app.save_path = fixture.path_join("legacy-v4.json")
	app.web_mode = false
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app._install_world(MountainManager.new(42))
	app.progression.total_xp = 6150
	app.progression.ranks = {"strength": 10, "endurance": 10, "recovery": 9}
	app.boulder.apply_progression(app.progression.ranks)
	app.boulder.distance = 45.0
	app.boulder.velocity = 0.0
	app.boulder.stamina = 117.5
	var payload: Dictionary = app._save_payload()
	report.check(payload.version == 4 and payload.progression.version == 1, "existing envelope v4 and progression v1 retained")
	report.check(not payload.has("first_summit_run_number") and not payload.has("first_reach_flags"), "no new prestige or milestone save fields")
	report.check(app._write_save_file(payload) == OK, "legacy fixture written only to isolated .tools path")
	var stored_hash: String = FileAccess.get_sha256(app.save_path)
	app.progression = Growth.new()
	app._load_save()
	report.check(not app.save_blocked and app.has_resume, "real Main loads isolated v4 save")
	report.check(app.progression.snapshot() == payload.progression, "XP and all saved ranks retained exactly")
	report.check(FileAccess.get_sha256(app.save_path) == stored_hash, "loading does not rewrite the save")
	report.check(is_equal_approx(app.boulder.max_stamina, 120.0) and is_equal_approx(app.boulder.stamina, 117.5), "saved stamina and growth physics unchanged")
	app.screen = "game"
	app.paused = true
	report.check(not app.choose_upgrade("recovery"), "paused game cannot purchase")
	app.paused = false
	app.boulder.distance = 20.0
	report.check(not app.choose_upgrade("recovery"), "slope cannot purchase")
	app.boulder.distance = 45.0
	app.boulder.velocity = 0.1
	report.check(not app.choose_upgrade("recovery"), "moving shelf cannot purchase")
	app.boulder.velocity = 0.0
	report.check(app.choose_upgrade("recovery"), "safe stationary shelf still supports final existing rank")
	report.check(app.progression.total_xp == 6150 and app.progression.ranks.recovery == 10 and app.progression.pending_points() == 0, "upgrade consumes pending point, never XP")
	report.check(not app.choose_upgrade("recovery") and not app.choose_upgrade("special"), "30 rank cap and unsupported special remain enforced")
	var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(app.save_path))
	var after_keys: Array = after.keys()
	var before_keys: Array = payload.keys()
	var after_growth_keys: Array = after.progression.keys()
	var before_growth_keys: Array = payload.progression.keys()
	after_keys.sort()
	before_keys.sort()
	after_growth_keys.sort()
	before_growth_keys.sort()
	report.check(after_keys == before_keys and after_growth_keys == before_growth_keys, "existing save field set unchanged after purchase")
	app.sound.shutdown()
	app.free()
	await process_frame
	quit(report.finish("save_compatibility", {"scope": "Real legacy Main v4 fixture round trip and safe-upgrade path; no user save or browser storage accessed", "fixture": fixture}))
