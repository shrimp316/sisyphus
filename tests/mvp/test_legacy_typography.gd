extends SceneTree

# Exercise the legacy canvas centering helper without drawing, then measure
# actual localized button and narrative strings at the three requested sizes.
class TextProbe extends "res://scripts/main.gd":
	var text_calls: Array[Dictionary] = []
	func _text(text: String, point: Vector2, size: int = 16, color: Color = INK, face: Font = null) -> void:
		text_calls.append({"text":text, "point":point, "size":size, "face":face, "color":color})

var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920,1080)
	root.add_child(viewport)
	var scene := TextProbe.new()
	# Never read or change an actual game save.
	scene.save_path = "user://legacy-typography-%s.json" % Time.get_ticks_usec()
	viewport.add_child(scene)
	await process_frame
	check(scene.font.resource_path == "res://ui/themes/typography/hud.tres", "default HUD and existing Latin logo retain their font")
	check(scene.menu_font.resource_path == "res://ui/themes/typography/menu.tres", "menu font variation")
	check(scene.title_font.resource_path == "res://ui/themes/typography/title.tres", "title font variation")
	check(scene.narrative_font.resource_path == "res://ui/themes/typography/narrative.tres", "narrative font variation")
	check(scene.Typography.load_font("res://missing-font-for-test.tres") == scene.KOREAN_FONT, "missing font uses bundled fallback")
	check(scene._text_width("F11 전체 화면   ·   M 소리",12,scene.narrative_font) <= 230.0, "title footer stays within right margin")
	var buttons: Array = [
		["이어 오르기  ↵",290.0], ["돌 앞에 서기  ↵",290.0], ["계속 오르기  ·  Esc",340.0],
		["소리 켜기",340.0], ["소리 끄기",340.0], ["저장하고 처음 화면으로",340.0],
		["저장 후 종료",340.0], ["다시 돌 앞에 서기  ↵",320.0], ["새로운 등반  ↵",300.0]
	]
	var prose: Array = [
		["시 지 프 스",19,scene.title_font], ["이번 등반이 남긴 힘",30,scene.title_font],
		["잠시, 숨을 고르다",32,scene.title_font], ["돌은 다시, 산 아래에",35,scene.title_font], ["정상",42,scene.title_font],
		["이번에는, 조금 더 올라갈 수 있을 것 같다.",19,scene.narrative_font],
		["5초마다 현재 진행을 자동 저장합니다. 저장은 이 브라우저에만 남습니다.",15,scene.narrative_font],
		["종료할 때 현재 위치가 저장됩니다. 추락을 되돌리는 체크포인트는 없습니다.",15,scene.narrative_font],
		["다음 산길은 조금 다를 것이다. 오르는 사람도.",17,scene.narrative_font],
		["잠시, 아무것도 밀지 않아도 된다.",22,scene.narrative_font]
	]
	for dimensions: Vector2i in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1280,720)]:
		viewport.size = dimensions
		await process_frame
		for pair: Array in buttons:
			var width: float = scene._text_width(pair[0],17,scene.menu_font)
			var font_height: float = scene.menu_font.get_height(scene._ui_font_size(17))
			check(width <= float(pair[1]) - 16.0, "button text fits %s at %s" % [pair[0],dimensions])
			check(font_height <= 54.0, "button text height fits %s at %s" % [pair[0],dimensions])
		for entry: Array in prose:
			var text: String = entry[0]
			var size: int = entry[1]
			var face: Font = entry[2]
			var width: float = scene._text_width(text,size,face)
			check(width <= float(dimensions.x) - 64.0, "centered text fits %s at %s" % [text,dimensions])
			scene._center(text, 100.0, size, Color.WHITE, face)
			var call: Dictionary = scene.text_calls.back()
			check(call.face == face and is_equal_approx(call.point.x,(dimensions.x-width)/2.0), "centering and rendering font agree %s at %s" % [text,dimensions])
	# A call without a face is the established HUD/Latin logo behavior.
	scene._center("S I S Y P H U S", 100.0, 62)
	check(scene.text_calls.back().face == null, "Latin logo keeps the default font")
	print(JSON.stringify({"suite":"legacy_typography", "checks":checks,"failures":failures,
		"scope":"headless font metrics and center helper; visual pixel comparison and Web are separate"}))
	quit(0 if failures.is_empty() else 1)
