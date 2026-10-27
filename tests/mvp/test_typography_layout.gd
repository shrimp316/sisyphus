extends SceneTree
# Structural font-metric and data-binding checks at three 16:9 sizes. The UI
# uses a single 1920x1080 design canvas scaled by the viewport; these checks
# do not substitute for screenshots or platform-specific visual inspection.
const Profile = preload("res://scripts/mastery_progression.gd")
const Board = preload("res://scenes/mvp/mastery_board.tscn")
const Menu = preload("res://scenes/mvp/main_menu.tscn")
var failures: Array[String] = []
var checks := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func run():
	var profile = Profile.new()
	profile.begin_run("typography-layout-agent")
	profile.award_distance(1000, 1000)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920,1080)
	root.add_child(viewport)
	var board = Board.instantiate()
	viewport.add_child(board)
	board.refresh(profile, true)
	var menu = Menu.instantiate()
	viewport.add_child(menu)
	menu.refresh(profile, false)
	await process_frame
	check(board.title_label.theme_type_variation == &"SisyphusTitleLabel" and board.title_label.get_theme_font_size("font_size") == 46, "title role")
	check(board.exp_label.get_theme_font_size("font_size") == 28, "wallet HUD role")
	check(board.detail_name.get_theme_font_size("font_size") == 23, "name role")
	check(board.detail_description.get_theme_font_size("font_size") == 21, "description role")
	check(board.detail_cost.get_theme_font_size("font_size") == 28, "cost role")
	check(board.detail_unlock.get_theme_font_size("font_size") == 19, "unlock role")
	check(menu.controls.new_game.get_theme_font_size("font_size") == 30, "menu role")
	check(board.slots.STR01.get_theme_font_size("font_size") == 23, "node button role")
	board.select_node("SPC01")
	check(board.detail_name.get_theme_color("font_color").is_equal_approx(Color("e8bd78")), "special node name highlighted")
	board.select_node("STR01")
	check(not board.detail_name.has_theme_color_override("font_color"), "ordinary node restores theme color")
	for id: String in menu.controls:
		var button: Button = menu.controls[id]
		var font: Font = button.get_theme_font("font")
		var actual_width: float = font.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
		var content_margins: float = button.get_theme_stylebox("normal").get_minimum_size().x
		check(actual_width + content_margins <= button.size.x, "menu button content width %s" % id)
	for sample: String in ["2,250 EXP", "999,999 EXP"]:
		var width: float = menu.wallet.get_theme_font("font").get_string_size(sample,HORIZONTAL_ALIGNMENT_LEFT,-1,menu.wallet.get_theme_font_size("font_size")).x
		check(width <= menu.wallet.size.x, "menu wallet width %s" % sample)
	for child: Node in board.canvas.get_children():
		if child is Label and child.theme_type_variation == &"SisyphusSectionLabel":
			var width: float = child.get_theme_font("font").get_string_size(child.text,HORIZONTAL_ALIGNMENT_LEFT,-1,child.get_theme_font_size("font_size")).x
			var allotted_width: float = 400.0 if child.position.y == 140.0 else 1230.0
			check(width <= allotted_width and child.size.x <= allotted_width, "board section width %s" % child.text)
	for res: Vector2i in [Vector2i(1920,1080), Vector2i(1600,900), Vector2i(1280,720)]:
		viewport.size = res
		await process_frame
		check(is_equal_approx(board.canvas.scale.x, float(res.x)/1920.0), "canvas scale %s" % res)
		for definition: Dictionary in profile.definitions:
			board.select_node(definition.id)
			await process_frame
			check(board.detail_name.text.contains(str(definition.name)), "name content %s" % definition.id)
			check(board.detail_description.text == str(definition.description), "description content %s" % definition.id)
			check(board.detail_cost.text.contains(str(definition.exp_cost)), "cost content %s" % definition.id)
			check(board.detail_unlock.text.contains(str(int(definition.unlock_milestone))), "unlock content %s" % definition.id)
			for field: Label in [board.detail_name,board.detail_description,board.detail_cost,board.detail_unlock]:
				var fontsize: int = field.get_theme_font_size("font_size")
				var font: Font = field.get_theme_font("font")
				var needed_height: float = field.get_line_count() * font.get_height(fontsize)
				check(needed_height <= field.size.y + 1.0, "%s vertical bounds for %s (%s > %s)" % [field.theme_type_variation,definition.id,needed_height,field.size.y])
			var cost_width: float = board.detail_cost.get_theme_font("font").get_string_size(board.detail_cost.text,HORIZONTAL_ALIGNMENT_LEFT,-1,board.detail_cost.get_theme_font_size("font_size")).x
			check(cost_width <= board.detail_cost.size.x, "cost width %s" % definition.id)
	print(JSON.stringify({"suite":"typography_layout", "checks":checks,"failures":failures,"resolutions":["1920x1080","1600x900","1280x720"],"scope":"1920 design canvas uniformly scaled; bindings and font metrics, not screenshots or OS-specific rendering"}))
	quit(0 if failures.is_empty() else 1)
