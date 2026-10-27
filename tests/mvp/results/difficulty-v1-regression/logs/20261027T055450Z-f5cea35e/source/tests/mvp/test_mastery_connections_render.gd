extends SceneTree
## Run with a real renderer (no --headless); a SubViewport samples the visible connector.
const Board = preload("res://scenes/mvp/mastery_board.tscn")
const Profile = preload("res://scripts/mastery_progression.gd")
const UI = preload("res://scripts/mvp/ui_theme.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("This render check requires a real display/rendering driver.")
		quit(2)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920,1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var board = Board.instantiate()
	viewport.add_child(board)
	var profile = Profile.new()
	profile.begin_run("render-fixture")
	profile.award_distance(250,1000)
	profile.purchase_node("STR01")
	board.refresh(profile,true)
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered: Image = viewport.get_texture().get_image()
	# STR01 ends at x260, STR02 begins at x275. Their connector crosses this gap.
	var sample: Color = rendered.get_pixel(267,259)
	var difference: float = Vector3(sample.r,sample.g,sample.b).distance_to(Vector3(UI.GOLD.r,UI.GOLD.g,UI.GOLD.b))
	var passed: bool = difference < .02 and board.connection_segments.size() == 27
	var image_path: String = "res://tests/mvp/results/mastery-board-render.png"
	var error: int = rendered.save_png(image_path)
	var report: Dictionary = {"renderer":DisplayServer.get_name(),"size":[1920,1080],"connector_sample":[267,259],
		"sample_rgb":[sample.r,sample.g,sample.b],"gold_rgb":[UI.GOLD.r,UI.GOLD.g,UI.GOLD.b],
		"rgb_distance":difference,"connections":board.connection_segments.size(),"visible_connector":passed,
		"png_saved":error==OK,"png_sha256":FileAccess.get_sha256(image_path)}
	var output = FileAccess.open("res://tests/mvp/results/mastery-connections-render.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	viewport.queue_free()
	await process_frame
	quit(0 if passed and error==OK else 1)
