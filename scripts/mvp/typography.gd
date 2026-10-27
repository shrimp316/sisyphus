extends RefCounted

# A damaged or incomplete font package must still leave the MVP readable.
# The legacy Korean font is already bundled; the Greek face is also bundled.
const BACKUP_FONT: Font = preload("res://assets/fonts/NotoSansKR.ttf")
const THEME_PATH: String = "res://ui/themes/sisyphus_theme.tres"
const HUD_PATH: String = "res://ui/themes/typography/hud.tres"
const GREEK_PATH: String = "res://assets/fonts/gfs_didot/GFSDidot-Regular.ttf"

static func load_font(path: String = HUD_PATH) -> Font:
	var selected: Font = load(path) as Font if ResourceLoader.exists(path) else null
	return resolve_font(selected)

static func resolve_font(selected: Font) -> Font:
	if selected == null or (selected is FontVariation and selected.base_font == null): return BACKUP_FONT
	if selected is FontVariation and not selected.base_font.has_char(65): return BACKUP_FONT
	return selected

static func load_theme(path: String = THEME_PATH) -> Theme:
	var selected: Theme = load(path) as Theme if ResourceLoader.exists(path) else null
	return resolve_theme(selected)

static func resolve_theme(selected: Theme) -> Theme:
	var required_roles: Array[String] = ["SisyphusTitleLabel", "SisyphusSectionLabel", "SisyphusNodeLabel",
		"SisyphusBodyLabel", "SisyphusHUDLabel", "SisyphusTooltipLabel", "SisyphusGreekLabel",
		"SisyphusNarrativeLabel", "SisyphusMenuButton", "SisyphusPrimaryButton",
		"SisyphusSecondaryButton", "SisyphusNodeButton"]
	var valid: bool = selected != null
	if valid:
		for role: String in required_roles:
			# has_font() also reports the default font; inspect the role's own
			# entries so a partially loaded variation cannot silently pass.
			if not "font" in selected.get_font_list(role):
				valid = false
				break
			var face: Font = selected.get_font("font", role)
			if face == null or (face is FontVariation and (face.base_font == null or not face.base_font.has_char(65))):
				valid = false
				break
	if valid: return selected
	var fallback := Theme.new()
	var safe_font := FontVariation.new()
	safe_font.base_font = BACKUP_FONT
	var greek: Font = load(GREEK_PATH) as Font if ResourceLoader.exists(GREEK_PATH) else null
	if greek != null: safe_font.fallbacks = [greek]
	fallback.default_font = safe_font
	fallback.default_font_size = 21
	var roles: Dictionary = {
		"SisyphusTitleLabel":["Label",46], "SisyphusSectionLabel":["Label",32],
		"SisyphusNodeLabel":["Label",23], "SisyphusBodyLabel":["Label",21],
		"SisyphusHUDLabel":["Label",28], "SisyphusTooltipLabel":["Label",19],
		"SisyphusGreekLabel":["Label",38], "SisyphusNarrativeLabel":["Label",30],
		"SisyphusMenuButton":["Button",30], "SisyphusPrimaryButton":["Button",30],
		"SisyphusSecondaryButton":["Button",30], "SisyphusNodeButton":["Button",23],
	}
	for role: String in roles:
		fallback.set_type_variation(role, roles[role][0])
		fallback.set_font("font",role,safe_font)
		fallback.set_font_size("font_size",role,roles[role][1])
		fallback.set_color("font_color",role,Color("dfd0af"))
	return fallback
