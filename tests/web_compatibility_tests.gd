extends SceneTree

# Browser backends are simulated; the browser smoke test covers actual JS/IDB.
class WebMain:
	extends "res://scripts/main.gd"
	var mirror_read: Dictionary = {"ok": true, "data": ""}
	var mirror_ok: bool = true
	var persistent: bool = true
	var written_mirror: String = ""
	var write_error: Error = OK
	var writes: int = 0
	func _read_web_mirror() -> Dictionary:
		return mirror_read
	func _write_web_mirror(payload: String) -> bool:
		written_mirror = payload
		return mirror_ok
	func _web_userfs_persistent() -> bool:
		return persistent
	func _write_save_file(payload: Dictionary) -> Error:
		writes += 1
		return super._write_save_file(payload) if write_error == OK else write_error

var checks: int = 0
var failures: int = 0
var fixture: String
var sequence: int = 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1

func fresh() -> WebMain:
	sequence += 1
	var app := WebMain.new()
	app.save_path = fixture.path_join("save-%d.json" % sequence)
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.web_mode = true
	return app

func put(app: WebMain, contents: String) -> void:
	var file := FileAccess.open(app.save_path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()

func payload(app: WebMain, stamp: float, distance: float) -> Dictionary:
	var data: Dictionary = app._save_payload()
	data.saved_at_unix_msec = stamp
	data.run.distance = distance
	data.run.peak = distance
	data.best = distance
	return data

func dispose(app: WebMain) -> void:
	app.free()

func run() -> void:
	fixture = "res://.tools/web-compat-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	var app := fresh()
	check(app.font is SystemFont, "desktop keeps system font selection")
	check(app.KOREAN_FONT.get_string_size("시지프스 저장 계속").x > 0.0, "bundled Korean font resolves without browser system fonts")
	var old := payload(app, 100.0, 12.0)
	var recent := payload(app, 200.0, 48.0)
	put(app, JSON.stringify(old))
	app.mirror_read.data = JSON.stringify(recent)
	app._load_save()
	check(app.has_resume and app.boulder.distance == 48.0, "newer synchronous mirror wins over stale IDB file")
	put(app, JSON.stringify(payload(app, 300.0, 72.0)))
	app._load_save()
	check(app.boulder.distance == 72.0, "newer IDB file wins over stale mirror")
	dispose(app)
	app = fresh()
	app.mirror_read.data = JSON.stringify(recent)
	app._load_save()
	check(app.has_resume and app.boulder.distance == 48.0, "mirror restores when IDB file is absent")
	dispose(app)
	for corrupt_primary: bool in [true, false]:
		app = fresh()
		var primary := "{broken" if corrupt_primary else JSON.stringify(old)
		put(app, primary)
		app.mirror_read.data = JSON.stringify(recent) if corrupt_primary else "{broken"
		app._load_save()
		check(app.save_blocked and not app.has_resume, "invalid JSON backend blocks destructive replacement (%s)" % corrupt_primary)
		check(not app._save_for_web() and app.writes == 0 and FileAccess.get_file_as_string(app.save_path) == primary, "blocked save preserves original backend (%s)" % corrupt_primary)
		dispose(app)
	app = fresh()
	var invalid := recent.duplicate(true)
	invalid.world = {}
	put(app, JSON.stringify(old))
	app.mirror_read.data = JSON.stringify(invalid)
	app._load_save()
	check(app.save_blocked and not app.has_resume, "newest semantically invalid world is not silently replaced with older progress")
	dispose(app)
	app = fresh()
	var legacy := {"version": 1, "best": 23.0, "run": old.run}
	put(app, JSON.stringify(legacy))
	app._load_save()
	check(app.has_resume and not app.save_blocked and app.best == 23.0, "legacy timestamp-free save still loads")
	dispose(app)
	for availability: Array in [[true, OK, false], [false, OK, true], [true, ERR_CANT_CREATE, false], [false, OK, false], [false, ERR_CANT_CREATE, true]]:
		app = fresh()
		app.mirror_ok = availability[0]
		app.write_error = availability[1]
		app.persistent = availability[2]
		var expected: bool = app.mirror_ok or (app.write_error == OK and app.persistent)
		check(app._save_for_web() == expected and app.save_error.is_empty() == expected, "save outcome reflects durable backend availability %s" % str(availability))
		if app.mirror_ok and app.write_error == OK:
			check(JSON.parse_string(app.written_mirror) == JSON.parse_string(FileAccess.get_file_as_string(app.save_path)), "IDB and mirror receive identical complete world/run/timestamp")
		dispose(app)
	app = fresh()
	app._begin()
	app.boulder.advance(1.0, true, false, false)
	app._save_and_quit()
	check(app.screen == "title" and app.has_resume and not app.quitting and not app.sound.shutting_down, "web save returns to title without terminating engine or audio")
	app._begin()
	check(app.screen == "game" and app.boulder.distance > 0.0, "web continue retains saved session")
	var before: int = app.writes
	app._process(5.1)
	check(app.writes == before + 1, "active browser session autosaves after five seconds")
	app.paused = true
	before = app.writes
	app._process(10.0)
	check(app.writes == before, "paused session does not repeatedly autosave")
	app.paused = false
	app._web_page_hidden([])
	check(app.paused and app.writes == before + 1, "page hide pauses and synchronously mirrors session")
	app.mirror_ok = false
	app.persistent = false
	app._save_and_quit()
	check(app.screen == "game" and app.paused and not app.save_error.is_empty(), "failed web save stays paused and reports failure")
	dispose(app)
	app = fresh()
	app.mirror_read.ok = false
	app.persistent = false
	app._load_save()
	check(not app.web_notice.is_empty() and not app.save_blocked, "unavailable browser storage warns while permitting temporary play")
	dispose(app)
	print("WEB COMPATIBILITY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
