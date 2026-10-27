extends SceneTree

const THEME: Theme = preload("res://ui/themes/sisyphus_theme.tres")
const SAMPLE: PackedScene = preload("res://tests/mvp/typography_sample.tscn")
const Typography = preload("res://scripts/mvp/typography.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func covers(face: Font, character: int) -> bool:
	if face.has_char(character): return true
	for fallback: Font in face.fallbacks:
		if fallback.has_char(character): return true
	return false

func run() -> void:
	var definitions: Dictionary = {
		"SisyphusTitleLabel":["Label",46,"Hahmlet-Bold.otf","f0c781"],
		"SisyphusSectionLabel":["Label",32,"Hahmlet-SemiBold.otf","dfd0af"],
		"SisyphusNodeLabel":["Label",23,"Hahmlet-Medium.otf","dfd0af"],
		"SisyphusBodyLabel":["Label",21,"Pretendard-Regular.otf","d8ccb8"],
		"SisyphusHUDLabel":["Label",28,"Pretendard-SemiBold.otf","f0c781"],
		"SisyphusTooltipLabel":["Label",19,"Pretendard-Regular.otf","c7bba4"],
		"SisyphusGreekLabel":["Label",38,"GFSDidot-Regular.ttf","e8bd78"],
		"SisyphusNarrativeLabel":["Label",30,"Hahmlet-Regular.otf","dfd0af"],
		"SisyphusMenuButton":["Button",30,"Hahmlet-SemiBold.otf","e8d6b5"],
		"SisyphusPrimaryButton":["Button",30,"Hahmlet-SemiBold.otf","e8d6b5"],
		"SisyphusSecondaryButton":["Button",30,"Hahmlet-SemiBold.otf","e8d6b5"],
		"SisyphusNodeButton":["Button",23,"Hahmlet-Medium.otf","dfd0af"],
	}
	var required: String = "ΣΙΣΥΦΟΣ ΩΘΗΣΙΣ ἄνθρωπος ἀρετή 숙련의 석판 운명의 직조 근력 · 지구력 · 호흡 1,000 m 2,250 EXP +15% × → °"
	for variation: String in definitions:
		var expected: Array = definitions[variation]
		var face: FontVariation = THEME.get_font("font",variation) as FontVariation
		check(THEME.get_type_variation_base(variation) == expected[0], variation + " base type")
		check(face != null and face.base_font.resource_path.ends_with(expected[2]), variation + " family and weight")
		check(THEME.get_font_size("font_size",variation) == expected[1], variation + " size")
		check(THEME.get_color("font_color",variation).is_equal_approx(Color(expected[3])), variation + " color")
		if face == null: continue
		check(not face.fallbacks.is_empty(), variation + " explicit bundled fallbacks")
		for fallback: Font in face.fallbacks:
			check(not fallback is SystemFont and fallback.resource_path.begins_with("res://assets/fonts/"), variation + " fallback is bundled")
		for index: int in range(required.length()):
			var codepoint: int = required.unicode_at(index)
			if codepoint != 32: check(covers(face,codepoint), variation + " glyph U+%04X" % codepoint)
	var greek: FontVariation = THEME.get_font("font","SisyphusGreekLabel") as FontVariation
	for path: String in ["res://assets/fonts/NotoSansKR.ttf", "res://assets/fonts/gfs_didot/GFSDidot-Regular.ttf",
		"res://assets/fonts/hahmlet/Hahmlet-Regular.otf", "res://assets/fonts/hahmlet/Hahmlet-Medium.otf",
		"res://assets/fonts/hahmlet/Hahmlet-SemiBold.otf", "res://assets/fonts/hahmlet/Hahmlet-Bold.otf",
		"res://assets/fonts/pretendard/Pretendard-Regular.otf", "res://assets/fonts/pretendard/Pretendard-Medium.otf",
		"res://assets/fonts/pretendard/Pretendard-SemiBold.otf"]:
		var file: FontFile = load(path) as FontFile
		check(file != null and not file.allow_system_fallback, path + " system fallback disabled")
	var ancient: String = "ΣΙΣΥΦΟΣΩΘΗΣΙΣἄνθρωποςἀρετήἄνθρωποςἀρετή"
	for index: int in range(ancient.length()):
		var codepoint: int = ancient.unicode_at(index)
		check(greek.base_font.has_char(codepoint), "GFS Didot NFC/NFD U+%04X" % codepoint)
	check((THEME.default_font as FontVariation).base_font.resource_path.ends_with("Pretendard-Regular.otf"), "default font is bundled Pretendard")
	var menu_font: FontVariation = THEME.get_font("font","SisyphusMenuButton") as FontVariation
	var section_font: FontVariation = THEME.get_font("font","SisyphusSectionLabel") as FontVariation
	var body_font: FontVariation = THEME.get_font("font","SisyphusBodyLabel") as FontVariation
	var tooltip_font: FontVariation = THEME.get_font("font","SisyphusTooltipLabel") as FontVariation
	check(menu_font.base_font == section_font.base_font, "menu and section share one font file resource")
	check(body_font.base_font == tooltip_font.base_font, "body and tooltip share one font file resource")
	var backup_theme: Theme = Typography.load_theme("res://missing-typography-test.tres")
	check((backup_theme.default_font as FontVariation).base_font.resource_path.ends_with("NotoSansKR.ttf"), "missing theme uses bundled backup font")
	check(backup_theme.get_font_size("font_size","SisyphusHUDLabel") == 28, "fallback preserves role sizes")
	check(Typography.load_font("res://missing-font-test.tres").resource_path.ends_with("NotoSansKR.ttf"), "missing HUD font uses bundled backup")
	var broken_face := FontVariation.new()
	check(Typography.resolve_font(broken_face).resource_path.ends_with("NotoSansKR.ttf"), "font with missing base uses bundled backup")
	broken_face.base_font = FontFile.new()
	check(Typography.resolve_font(broken_face).resource_path.ends_with("NotoSansKR.ttf"), "empty font data uses bundled backup")
	var broken_theme := Theme.new()
	broken_theme.merge_with(THEME)
	broken_theme.clear_font("font", "SisyphusHUDLabel")
	check((Typography.resolve_theme(broken_theme).default_font as FontVariation).base_font.resource_path.ends_with("NotoSansKR.ttf"), "partially loaded theme uses bundled backup")
	check(Typography.resolve_theme(THEME) == THEME, "complete theme is reused")
	var sample: Control = SAMPLE.instantiate()
	root.add_child(sample)
	await process_frame
	check(sample.get_node("GreekAccents").get_theme_font("font").resource_path.ends_with("greek.tres"), "sample scene resolves Greek font")
	check(sample.get_node("Values").get_theme_font_size("font_size") == 28, "sample scene resolves HUD size")
	sample.queue_free()
	print(JSON.stringify({"suite":"typography_fonts","checks":checks,"failures":failures,"scope":"font coverage and theme configuration; visual shaping and platform rendering require screenshots"}))
	quit(0 if failures.is_empty() else 1)
