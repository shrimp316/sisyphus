extends "res://scripts/mvp/design_canvas.gd"

const UI = preload("res://scripts/mvp/ui_theme.gd")
const NodeSlot = preload("res://scenes/mvp/mastery_node.tscn")
signal closed
signal purchase_requested(node_id: String)
var slots: Dictionary = {}
var profile: RefCounted
var selection: String = "STR01"
var purchase_allowed: bool = false
var title_label: Label
var exp_label: Label
var detail: Label
var buy: Button
var notice: Label
var connection_layer: Control
var connection_segments: Array[PackedVector2Array] = []

func _ready() -> void:
	super._ready()
	UI.backdrop(canvas, Rect2(0,0,1920,1080))
	# Sibling ordering puts the lines above the opaque backdrop and below slots.
	connection_layer = Control.new()
	connection_layer.name = "PrerequisiteConnections"
	connection_layer.size = Vector2(1920,1080)
	connection_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(connection_layer)
	connection_layer.draw.connect(_draw_connections)
	title_label = UI.label(canvas, "숙련의 석판", Rect2(70,35,1200,80),48,UI.GOLD)
	exp_label = UI.label(canvas, "", Rect2(1390,50,460,65),36,UI.GOLD)
	for i: int in range(3):
		UI.label(canvas, ["근력 · 돌을 미는 힘","지구력 · 오래 버티는 몸","호흡 · 되찾는 리듬"][i], Rect2(80+i*410,140,400,55),28)
	UI.label(canvas,"특별 숙련 · 첫 정상 이후의 흔적",Rect2(80,755,1230,55),28,UI.GOLD)
	UI.backdrop(canvas,Rect2(1370,150,480,770),Color("182120"))
	detail = UI.label(canvas,"",Rect2(1400,180,420,500),28)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buy = UI.button(canvas,"각인하기",Rect2(1410,710,400,80),func(): purchase_requested.emit(selection),true)
	notice = UI.label(canvas,"",Rect2(1400,820,420,120),24,UI.MUTED)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.button(canvas,"돌아가기",Rect2(80,970,260,75),func(): closed.emit())
	UI.label(canvas,"Tab / 방향키로 선택 · Enter 확인",Rect2(410,980,900,55),25,UI.MUTED)

func refresh(value: RefCounted, allowed: bool, heading: String = "숙련의 석판") -> void:
	profile = value
	purchase_allowed = allowed
	title_label.text = heading
	exp_label.text = "%d EXP" % profile.available_exp
	for definition: Dictionary in profile.definitions:
		var id: String = definition.id
		if not slots.has(id):
			var slot: Button = NodeSlot.instantiate()
			var index: int = int(definition.sequence)-1
			if definition.category == "SPC":
				slot.position = Vector2(80 + index*252, 825)
				slot.size = Vector2(232,108)
			else:
				var column: int = ["STR","END","BRE"].find(definition.category)
				slot.position = Vector2(80+column*410+(index%2)*195,215+floori(index/2.0)*103)
				slot.size = Vector2(180,88)
			canvas.add_child(slot)
			slot.pressed.connect(func(): select_node(id))
			slots[id] = slot
		slots[id].configure(definition, profile.get_node_state(id))
	select_node(selection)
	_rebuild_connections()

func select_node(id: String) -> void:
	selection = id
	var definition: Dictionary = profile.get_node_definition(id)
	if definition.is_empty(): return
	var state: String = profile.get_node_state(id)
	detail.text = "%s  ·  %s\n\n%s\n\n비용 %d EXP\n개방 기록 %dm\n\n%s" % [id,definition.name,definition.description,definition.exp_cost,definition.unlock_milestone,"선행: "+", ".join(definition.prerequisites) if not definition.prerequisites.is_empty() else "선행 노드 없음"]
	buy.disabled = not purchase_allowed or not profile.can_purchase_node(id)
	notice.text = "첫 해금 안내 또는 정지한 쉼터에서 구매할 수 있습니다." if not purchase_allowed else {"purchased":"이미 새긴 숙련입니다.","locked":"먼저 해당 거리에 도달하세요.","disabled":"효과 검증 전에는 구매할 수 없습니다.","prerequisite":"같은 계열의 앞 노드를 먼저 새기세요.","insufficient_exp":"EXP가 부족합니다.","available":"확인 후 EXP를 사용해 각인합니다."}.get(state, "")

func _rebuild_connections() -> void:
	connection_segments.clear()
	for definition: Dictionary in profile.definitions:
		for prior: String in definition.prerequisites:
			if slots.has(prior) and slots.has(definition.id):
				var a: Vector2 = slots[prior].position + slots[prior].size*0.5
				var b: Vector2 = slots[definition.id].position + slots[definition.id].size*0.5
				connection_segments.append(PackedVector2Array([a,b]))
	connection_layer.queue_redraw()

func _draw_connections() -> void:
	for segment: PackedVector2Array in connection_segments:
		connection_layer.draw_line(segment[0],segment[1],UI.GOLD,2,true)
