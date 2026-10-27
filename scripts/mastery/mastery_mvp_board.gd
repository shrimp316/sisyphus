extends "res://scripts/mastery/mastery_screen.gd"
## Actual MVP UI. No fixture injection, model mutation or persistence lives here.
signal purchase_requested(node_id: String)
const LiveAdapter = preload("res://scripts/mastery/mastery_mvp_adapter.gd")
var profile: RefCounted
var purchase_allowed := false
var selection := "STR01"
var slots: Dictionary = {}
var close_button: Button
var context_notice: Label
var current_heading := "숙련의 석판"
var _previous_purchases: Array = []
var _previous_profile: RefCounted

func _ready() -> void:
	adapter = LiveAdapter.new()
	super._ready()
	for view in node_views.values():
		slots[LiveAdapter.model_id(view.data)] = view.hit_target
	close_button = Button.new()
	close_button.name = "ReturnToGame"
	close_button.text = "돌아가기"
	close_button.theme_type_variation = "SisyphusSecondaryButton"
	close_button.position = Vector2(140, 988)
	close_button.size = Vector2(250, 62)
	close_button.pressed.connect(close_screen)
	stage.add_child(close_button)
	context_notice = Art.label(stage, "PurchaseContext", "", Rect2(470, 310, 930, 40), "SisyphusTooltipLabel")
	context_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for direction in ["Prev", "Next"]:
		stage.get_node("Act" + direction).tooltip_text = "현재 1막 · 2~4막 준비 중"
	stage.get_node("InputHelp").text = "클릭 · Tab / Enter 선택   |   Esc 돌아가기"

func bind_profile(value: RefCounted, allowed: bool, heading: String, current_run: int = 1) -> void:
	var changed_profile: bool = _previous_profile != value
	var old_purchases: Array = [] if changed_profile else _previous_purchases.duplicate()
	profile = value
	purchase_allowed = allowed
	current_heading = heading
	adapter.bind(value, allowed, current_run)
	refresh()
	# Restore/open is static. Animate only a new purchase on an already bound profile.
	if not changed_profile:
		for id: String in profile.purchased_mastery_nodes:
			if id not in old_purchases and not id.begins_with("SPC"):
				_purchased(LiveAdapter.view_id(id))
	_previous_purchases = profile.purchased_mastery_nodes.duplicate()
	_previous_profile = profile

func _resolve_state(row: Dictionary, _snapshot: Dictionary) -> Dictionary:
	return adapter.resolve(row, selected_id)

func _update_header(snapshot: Dictionary, eligible: int, purchased: int) -> void:
	exp_label.text = "%d EXP" % int(snapshot.available_exp)
	progress_label.text = "구매 자격 %d / 35   ·   각인 %d / 35   ·   회차 %d" % [eligible, purchased, int(snapshot.current_run_number)]
	act_label.text = "제 I 막 · 세 가지 길" if current_heading == "숙련의 석판" else current_heading
	if context_notice != null:
		context_notice.text = "개방 안내 또는 정지한 쉼터에서 각인할 수 있습니다." if not purchase_allowed else "새길 숙련을 선택하세요. 확인 후 기존 EXP 비용이 적용됩니다."

func select_node(id: String) -> void:
	var ui_id: String = id if id.begins_with("act1_") else LiveAdapter.view_id(id)
	if not node_views.has(ui_id): return
	selection = LiveAdapter.model_id(node_views[ui_id].data)
	super.select_node(ui_id)

func _update_detail(_snapshot: Dictionary) -> void:
	if not node_views.has(selected_id): return
	var row: Dictionary = node_views[selected_id].data
	var state: Dictionary = node_views[selected_id].state
	var id: String = LiveAdapter.model_id(row)
	var special: bool = row.track == "special"
	if special:
		detail_name.text = "특별 숙련 %02d" % int(row.index)
		detail_effect.text = "효과 · 문자 미정\n\n특별 숙련 플레이스홀더"
		if state.purchased:
			detail_effect.text += "\n기존 구매·효과 유지"
		detail_requirement.text = "첫 정상 이후 다음 회차에 자격 개방.\n새로운 구매는 설계 확정 후 제공됩니다."
		detail_cost.text = "비용 미정"
		detail_state.text = "기존 기록 · 구매 완료" if state.purchased else "자격 개방 · 설계 대기" if state.eligible else "첫 정상 기록 필요"
	else:
		var definition: Dictionary = {} if profile == null else profile.get_node_definition(id)
		detail_name.text = str(definition.get("name", "%s %02d" % [NAMES[row.track], int(row.index)]))
		detail_effect.text = str(definition.get("description", "진행 기록을 불러오는 중입니다."))
		var prerequisites: Array = definition.get("prerequisites", [])
		detail_requirement.text = "최초 %d m 도달\n%s" % [int(definition.get("unlock_milestone", row.milestone_m)), "선행 노드 없음" if prerequisites.is_empty() else "선행: " + ", ".join(prerequisites)]
		detail_cost.text = "%d EXP" % int(definition.get("exp_cost", 0))
		var states := {"disabled": "현재 비활성", "locked": "도달 조건 미충족", "prerequisite": "선행 각인 필요", "available": "각인 가능", "insufficient_exp": "EXP 부족", "purchased": "각인 완료"}
		detail_state.text = str(states.get(state.model_state, "구매 불가"))
		if state.can_purchase == false and state.model_state == "available": detail_state.text = "정지한 쉼터에서 각인"
	purchase_button.disabled = not state.can_purchase
	purchase_button.text = "각인하기" if state.can_purchase else ("구매 완료" if state.purchased else "구매 미정") if special else detail_state.text
	for view in node_views.values():
		view.hit_target.tooltip_text = "%s %02d · 클릭하여 상세 보기" % [NAMES[view.data.track], int(view.data.index)]

func can_request_purchase(id: String) -> bool:
	return adapter.can_request_purchase(id)

func purchase_selected() -> bool:
	if not can_request_purchase(selection): return false
	purchase_requested.emit(selection)
	return true # Accepted confirmation request; purchase has NOT happened here.

func play_unlock(distance: int) -> void:
	skip_animations()
	if distance in [150, 400, 700]:
		for i in 3: gate_views[i].play()

func _unhandled_key_input(_event: InputEvent) -> void:
	# The host owns Esc so it can dismiss a purchase confirmation before the board.
	pass
