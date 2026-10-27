extends "res://scripts/mvp/design_canvas.gd"

const UI = preload("res://scripts/mvp/ui_theme.gd")
# The current menu renders its existing logo as text. Preserve its original
# appearance until the supplied logo artwork can be used without alteration.
const LEGACY_LOGO_FONT: Font = preload("res://assets/fonts/NotoSansKR.ttf")
signal requested(action: String)
var controls: Dictionary = {}
var record: Label
var wallet: Label
var history: Label

func _ready() -> void:
	super._ready()
	for id: String in ["sky", "far", "mid", "ruins", "slope"]:
		UI.image(canvas, id, Rect2(0, 0, 1920, 1080))
	UI.image(canvas, "boulder_shadow", Rect2(950, 730, 380, 120))
	UI.image(canvas, "boulder", Rect2(1005, 405, 390, 390))
	# Existing single-sprite fallback, in front so the hands remain visible.
	UI.image(canvas, "sisyphus", Rect2(690, 455, 390, 477))
	UI.image(canvas, "foreground", Rect2(0, 0, 1920, 1080))
	UI.backdrop(canvas, Rect2(55, 290, 505, 710), Color(0.02, 0.04, 0.04, 0.62))
	var logo: Label = UI.label(canvas, "ΣΙΣΥΦΟΣ", Rect2(85, 55, 800, 110), 84, Color("d6b777"))
	logo.add_theme_font_override("font", LEGACY_LOGO_FONT)
	logo.add_theme_color_override("font_outline_color", Color(0.0,0.0,0.0,0.85))
	logo.add_theme_constant_override("outline_size", 1)
	logo.add_theme_color_override("font_shadow_color", Color(0.0,0.0,0.0,0.65))
	logo.add_theme_constant_override("shadow_offset_x", 1)
	logo.add_theme_constant_override("shadow_offset_y", 1)
	UI.label(canvas, "시지프스 · 끝나지 않는 등반", Rect2(92, 170, 800, 60), 30, UI.TEXT, &"SisyphusNarrativeLabel")
	var entries: Array = [["continue", "이어하기"], ["new_game", "새로운 등반"], ["mastery", "숙련의 석판"], ["sephirot", "운명의 직조"], ["settings", "설정"], ["help", "조작법"]]
	for i: int in range(entries.size()):
		var id: String = entries[i][0]
		controls[id] = UI.button(canvas, entries[i][1], Rect2(88, 320 + i * 100, 440, 84), func(): requested.emit(id), i == 0, &"SisyphusMenuButton")
	UI.image(canvas, "progress_panel", Rect2(1460, 290, 370, 570))
	UI.label(canvas, "제 I 막", Rect2(1540, 325, 240, 70), 32, UI.TEXT, &"SisyphusSectionLabel")
	UI.label(canvas, "최고 도달 거리", Rect2(1540, 415, 240, 45), 19, UI.MUTED, &"SisyphusTooltipLabel")
	record = UI.label(canvas, "0m", Rect2(1540, 460, 240, 80), 28, UI.GOLD, &"SisyphusHUDLabel")
	wallet = UI.label(canvas, "0 EXP", Rect2(1540, 565, 240, 55), 28, UI.GOLD, &"SisyphusHUDLabel")
	history = UI.label(canvas, "돌은 다시 오를 것이다.", Rect2(1540, 650, 240, 150), 21, UI.TEXT, &"SisyphusBodyLabel")
	history.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.label(canvas, "D 밀기   ·   Shift 힘주기   ·   Space 버티기", Rect2(88, 1000, 1200, 50), 19, UI.MUTED, &"SisyphusTooltipLabel")
	UI.label(canvas, "Enter 선택 / Tab 이동", Rect2(1430, 1000, 440, 50), 19, UI.MUTED, &"SisyphusTooltipLabel")

func refresh(profile: RefCounted, can_resume: bool) -> void:
	controls.continue.disabled = not can_resume
	controls.sephirot.visible = profile.sephirot_unlocked
	# Locked nodes can be inspected before the first milestone; buying stays guarded.
	controls.mastery.disabled = false
	record.text = "%.0fm" % profile.highest_distance
	wallet.text = "%d EXP" % profile.available_exp
	history.text = "프레스티지 %d회\n말쿠트 · EXP ×5\n운명의 실 %d개" % [profile.prestige_count, profile.threads_balance] if profile.first_summit_completed else "아직 끝을 알 수 없는 길.\n발걸음은 기록으로 남는다."
	if visible: (controls.continue if can_resume else controls.new_game).grab_focus()
