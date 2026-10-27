extends Control
## Developer controls exist only in this independent preview scene.
const ScreenScene = preload("res://godot/scenes/mastery/mastery_tablet_screen.tscn")
const MockAdapter = preload("res://scripts/mastery/mastery_progress_adapter.gd")
const Art = preload("res://scripts/mastery/mastery_art.gd")
var screen
var controls: Control
var status: Label
var adapter = MockAdapter.new()

func _ready() -> void:
	theme = preload("res://ui/themes/sisyphus_theme.tres")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	adapter.apply_fixture("zero")
	screen = ScreenScene.instantiate()
	screen.set_adapter(adapter)
	add_child(screen)
	controls = Control.new()
	controls.name = "PreviewControls"
	controls.size = Vector2(1920, 1080)
	controls.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(controls)
	status = Art.label(controls, "PreviewNotice", "독립 UI 프리뷰 · 실제 저장과 연결되지 않습니다", Rect2(530, 311, 860, 35), "SisyphusTooltipLabel")
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(MockAdapter.FIXTURES))
	for i in fixtures.size():
		var fixture: Dictionary = fixtures[i]
		_button(fixture.label, Rect2(140 + i * 157, 941, 150, 43), _fixture.bind(str(fixture.id)))
	_button("연출 건너뛰기", Rect2(1100, 941, 235, 43), screen.skip_animations)
	_button("30점 시연", Rect2(140, 995, 180, 43), adapter.fund_preview)
	_button("구매 초기화", Rect2(335, 995, 180, 43), adapter.reset_purchased)
	screen.state_presented.connect(_state_log)
	screen.closed.connect(func(): status.text = "프리뷰 닫힘 · 진행 상태 버튼을 눌러 다시 열기")
	resized.connect(_fit)
	_fit()
	print("MASTERY_PREVIEW_READY nodes=", screen.node_views.size())
	_state_log("zero", 0)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mastery-fixture="):
			_fixture(argument.trim_prefix("--mastery-fixture="), false)

func _button(text: String, rect: Rect2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.theme_type_variation = "SisyphusSecondaryButton"
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(action)
	controls.add_child(button)
	return button

func _fixture(id: String, animate: bool = true) -> void:
	screen.show()
	status.text = "독립 UI 프리뷰 · 실제 저장과 연결되지 않습니다"
	screen.apply_fixture(id, animate)

func _state_log(id: String, eligible: int) -> void:
	print("MASTERY_PREVIEW_STATE ", JSON.stringify({"fixture": id, "eligible": eligible, "selected": screen.selected_id, "purchased": 30 - adapter.snapshot().pending_points if adapter.snapshot().total_xp == 6150 else null}))

func _fit() -> void:
	var factor: float = minf(size.x / 1920.0, size.y / 1080.0)
	controls.scale = Vector2.ONE * factor
	controls.position = (size - Vector2(1920, 1080) * factor) * 0.5
