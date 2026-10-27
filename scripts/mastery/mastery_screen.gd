extends Control
signal closed
signal state_presented(fixture_id: String, eligible: int)
const Art = preload("res://scripts/mastery/mastery_art.gd")
const Loader = preload("res://scripts/mastery/mastery_layout_loader.gd")
const Resolver = preload("res://scripts/mastery/mastery_state_resolver.gd")
const MockAdapter = preload("res://scripts/mastery/mastery_progress_adapter.gd")
const TrackScene = preload("res://godot/scenes/mastery/mastery_track.tscn")
const GateScene = preload("res://godot/scenes/mastery/mastery_gate.tscn")
const NAMES := {"strength": "근력", "endurance": "지구력", "breath": "호흡", "special": "특별 숙련"}
const EFFECTS := {"strength": "밀기 힘", "endurance": "최대 스태미나", "breath": "회복 속도"}
const STATUS_NAMES := {"STORY_LOCKED": "도달 조건 미충족", "LOCKED": "선행 강화 필요", "AVAILABLE": "강화 가능", "INSUFFICIENT_EXP": "강화점 없음", "PURCHASED": "강화 완료"}
var adapter
var rows: Array[Dictionary] = []
var node_views: Dictionary = {}
var track_views: Dictionary = {}
var gate_views: Array = []
var stage: Control
var selected_id := "act1_strength_01"
var exp_label: Label
var progress_label: Label
var act_label: Label
var detail_name: Label
var detail_effect: Label
var detail_requirement: Label
var detail_cost: Label
var detail_state: Label
var purchase_button: Button
var opening := true

func _ready() -> void:
	theme = preload("res://ui/themes/sisyphus_theme.tres")
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage = Control.new()
	stage.name = "Stage"
	stage.size = Vector2(1920, 1080)
	stage.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(stage)
	Art.image(stage, "Background", "background/slate_bg_main.png", Rect2(0, 0, 1920, 1080))
	var title := Art.label(stage, "Title", "숙련의 석판", Rect2(700, 90, 520, 65), "SisyphusTitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	act_label = Art.label(stage, "ActInfo", "제 I 막 · 세 가지 길", Rect2(700, 157, 520, 44), "SisyphusNodeLabel")
	act_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exp_label = Art.label(stage, "EXPInfo", "", Rect2(700, 207, 520, 40), "SisyphusHUDLabel")
	exp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label = Art.label(stage, "MasteryProgressInfo", "", Rect2(650, 265, 620, 36), "SisyphusTooltipLabel")
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows = Loader.load_nodes()
	for kind in ["strength", "endurance", "breath", "special"]:
		var filtered: Array[Dictionary] = []
		for row: Dictionary in rows:
			if row.track == kind: filtered.append(row)
		if filtered.is_empty(): continue
		var track = TrackScene.instantiate()
		stage.add_child(track)
		track.configure(kind, filtered)
		track_views[kind] = track
		for view in track.views:
			node_views[view.data.node_id] = view
			view.selected.connect(select_node)
	_build_detail()
	# The background already supplies the frame; avoid duplicating its edge artwork.
	# Its architecture is already in Background; do not hide the composed UI beneath it.
	_build_footer()
	for y in [434, 572, 708, 856]:
		var gate = GateScene.instantiate()
		stage.add_child(gate)
		gate.position = Vector2(285, y - 58)
		gate_views.append(gate)
	resized.connect(_fit)
	_fit()
	if adapter == null:
		var mock = MockAdapter.new()
		mock.apply_fixture("zero")
		set_adapter(mock)
	else: _connect_adapter()
	opening = false
	refresh()

func _build_detail() -> void:
	var panel := Control.new()
	panel.name = "DetailPanel"
	panel.position = Vector2(1432, 320)
	panel.size = Vector2(392, 660)
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	stage.add_child(panel)
	Art.image(panel, "PanelArt", "panels/detail_panel.png", Rect2(0, 0, 392, 660))
	detail_name = Art.label(panel, "NameLabel", "", Rect2(30, 32, 332, 65), "SisyphusSectionLabel")
	detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_effect = Art.label(panel, "EffectLabel", "", Rect2(36, 145, 320, 125))
	detail_requirement = Art.label(panel, "RequirementLabel", "", Rect2(36, 300, 320, 105), "SisyphusTooltipLabel")
	detail_cost = Art.label(panel, "CostLabel", "", Rect2(36, 425, 320, 75), "SisyphusHUDLabel")
	detail_state = Art.label(panel, "StateLabel", "", Rect2(36, 510, 320, 40), "SisyphusNodeLabel")
	for label: Label in [detail_effect, detail_requirement, detail_cost, detail_state]: label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	purchase_button = Button.new()
	purchase_button.name = "PurchaseButton"
	purchase_button.position = Vector2(38, 565)
	purchase_button.size = Vector2(316, 65)
	purchase_button.theme_type_variation = "SisyphusPrimaryButton"
	for style in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxTexture.new()
		box.texture = Art.texture("navigation/button_purchase_blank.png")
		box.modulate_color = Color(0.65, 0.65, 0.65) if style == "disabled" else Color.WHITE
		purchase_button.add_theme_stylebox_override(style, box)
	purchase_button.pressed.connect(purchase_selected)
	panel.add_child(purchase_button)

func _build_footer() -> void:
	Art.image(stage, "FooterPlaque", "navigation/header_text_blank_plaque.png", Rect2(670, 1003, 580, 74))
	var help := Art.label(stage, "InputHelp", "클릭 · Tab / Enter 선택   |   Esc 닫기", Rect2(670, 1023, 580, 34), "SisyphusTooltipLabel")
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for direction in ["prev", "next"]:
		var button := TextureButton.new()
		button.name = "Act" + direction.capitalize()
		button.texture_normal = Art.texture("navigation/arrow_%s.png" % direction)
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.position = Vector2(15 if direction == "prev" else 1808, 557)
		button.size = Vector2(96, 104)
		button.disabled = true
		button.modulate.a = 0.45
		button.tooltip_text = "1막 프리뷰 · 2~4막 규칙 미구현"
		stage.add_child(button)

func _fit() -> void:
	if stage == null: return
	var factor: float = minf(size.x / 1920.0, size.y / 1080.0)
	stage.scale = Vector2.ONE * factor
	stage.position = (size - Vector2(1920, 1080) * factor) * 0.5

func set_adapter(value) -> void:
	if adapter != null:
		if adapter.changed.is_connected(refresh): adapter.changed.disconnect(refresh)
		if adapter.purchase_succeeded.is_connected(_purchased): adapter.purchase_succeeded.disconnect(_purchased)
	adapter = value
	if is_node_ready():
		_connect_adapter()
		refresh()

func _connect_adapter() -> void:
	if not adapter.changed.is_connected(refresh): adapter.changed.connect(refresh)
	if not adapter.purchase_succeeded.is_connected(_purchased): adapter.purchase_succeeded.connect(_purchased)

func refresh() -> void:
	if adapter == null or stage == null: return
	var snapshot: Dictionary = adapter.snapshot()
	var eligible := 0
	var purchased := 0
	for id: String in node_views:
		var view = node_views[id]
		var state: Dictionary = _resolve_state(view.data, snapshot)
		view.apply_state(state)
		eligible += int(state.eligible)
		purchased += int(state.purchased)
	for track in track_views.values(): track.refresh_connectors()
	_update_header(snapshot, eligible, purchased)
	_update_detail(snapshot)
	state_presented.emit(str(snapshot.fixture_id), eligible)

func _resolve_state(row: Dictionary, snapshot: Dictionary) -> Dictionary:
	return Resolver.resolve(row, snapshot, selected_id)

func _update_header(snapshot: Dictionary, eligible: int, purchased: int) -> void:
	exp_label.text = "%s EXP  ·  강화점 %d" % [str(snapshot.total_xp), int(snapshot.pending_points)]
	progress_label.text = "구매 자격 %d / 35   ·   강화 %d / 30   ·   회차 %d" % [eligible, purchased, int(snapshot.current_run_number)]

func select_node(id: String) -> void:
	if not node_views.has(id): return
	selected_id = id
	refresh()

func _update_detail(snapshot: Dictionary) -> void:
	if not node_views.has(selected_id): return
	var row: Dictionary = node_views[selected_id].data
	var state: Dictionary = node_views[selected_id].state
	detail_name.text = "%s %02d" % [NAMES[row.track], int(row.index)]
	if row.track == "special":
		detail_effect.text = "효과 · 문자 미정\n\n개발 데이터\n특별 숙련 플레이스홀더"
		detail_requirement.text = "첫 정상 이후 다음 회차에 자격 개방.\n구매 기능은 아직 정의되지 않았습니다."
		detail_cost.text = "비용 미정"
		detail_state.text = "자격 개방 · 설계 대기" if state.eligible else ("첫 정상 기록 · 다음 회차 대기" if int(snapshot.first_summit_run_number) >= 0 else "첫 정상 기록 필요")
	else:
		detail_effect.text = "%s · 기본값의 +2%%\n\n현재 게임의 계열 강화 기준\n계열당 최대 10랭크 (+20%%)" % EFFECTS[row.track]
		detail_requirement.text = "최초 %d m 도달\n선행 %s %d랭크" % [int(row.milestone_m), NAMES[row.track], int(row.index) - 1]
		detail_cost.text = "강화점 1 필요\nEXP 직접 차감 없음"
		detail_cost.add_theme_font_size_override("font_size", 23)
		detail_state.text = STATUS_NAMES[state.base_state]
	purchase_button.disabled = not state.can_purchase
	purchase_button.text = "강화 시연" if state.can_purchase else "구매 불가" if row.track == "special" else STATUS_NAMES[state.base_state]

func purchase_selected() -> bool:
	if not node_views.has(selected_id): return false
	return adapter.purchase(node_views[selected_id].data)

func _purchased(id: String) -> void:
	if not node_views.has(id): return
	var view = node_views[id]
	view.flash()
	if int(view.data.index) == 10: track_views[view.data.track].resonate()

func apply_fixture(id: String, animate: bool = true) -> void:
	skip_animations()
	adapter.apply_fixture(id)
	# State is committed before any presentation-only animation starts.
	if not animate or id == "zero": return
	if id in ["250", "500", "750"]:
		for i in 3: gate_views[i].play()
	else: gate_views[3].play(true)

func skip_animations() -> void:
	for gate in gate_views: gate.skip()
	for view in node_views.values(): view.stop_animation()

func close_screen() -> void:
	skip_animations()
	hide()
	closed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_screen()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	skip_animations()
