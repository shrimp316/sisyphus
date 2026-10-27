extends "res://scripts/main.gd"

const Mastery = preload("res://scripts/mastery_progression.gd")
const MasteryStone = preload("res://scripts/mvp/climb_boulder.gd")
const SaveContract = preload("res://scripts/mvp/save_contract.gd")
const UI = preload("res://scripts/mvp/ui_theme.gd")
const MenuScene = preload("res://scenes/mvp/main_menu.tscn")
const BoardScene = preload("res://scenes/mvp/mastery_board.tscn")
const Canvas = preload("res://scripts/mvp/design_canvas.gd")
const PRESTIGE_PHASES: Array[String] = ["SUMMIT_REACHED","FIRST_SUMMIT_SEQUENCE","BOULDER_ROLLS_AWAY","PRESTIGE_COMMIT","SEPHIROT_REVEAL","MALKUTH_UNLOCK","NEW_RUN"]
var mastery: MasteryProgression = Mastery.new()
var menu: Control
var board: Control
var overlay: Control
var ui_layer: CanvasLayer
var ui_mode: String = ""
var board_return: String = "title"
var modal_milestone: Dictionary = {}
var prestige_phase: String = ""
var phase_elapsed: float = 0.0
var presentation: Label
var rolling_stone: TextureRect
var save_revision: int = 0
var integration_accumulator: float = 0.0
var transition_busy: bool = false
var persistence_failed: bool = false
var preferences: Dictionary = {"muted":false,"volume":0.7,"fullscreen":false}

func _init() -> void:
	save_path = "user://sisyphus-mvp-v1.json"
	mastery.begin_run()

func _ready() -> void:
	super._ready()
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 20
	add_child(ui_layer)
	menu = MenuScene.instantiate()
	ui_layer.add_child(menu)
	menu.requested.connect(_menu_action)
	board = BoardScene.instantiate()
	ui_layer.add_child(board)
	board.hide()
	board.closed.connect(_close_board)
	board.purchase_requested.connect(_confirm_purchase)
	_apply_preferences()
	if not web_mode and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if preferences.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	_show_title()

func _install_world(world: MountainManager) -> void:
	mountain = world
	path.curve = world.curve
	boulder = MasteryStone.new(mountain)
	boulder.apply_mastery_effects(mastery.get_mastery_modifiers())
	boulder.stamina = boulder.max_stamina
	gait_phase = 0.0
	character_travel = 0.0
	upgrade_open = false
	boulder.recovered.connect(_recovery_feedback)
	boulder.ledge_crossed.connect(_ledge_feedback)

func _refresh_upgrade_choice() -> void:
	upgrade_open = false

func choose_upgrade(_kind: String) -> bool:
	return false

func _physics_process(delta: float) -> void:
	advance_gameplay(delta, [Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT), Input.is_physical_key_pressed(KEY_SHIFT), Input.is_physical_key_pressed(KEY_SPACE)])

func advance_gameplay(delta: float, command: Array) -> void:
	if screen != "game" or paused or not prestige_phase.is_empty() or save_blocked or persistence_failed: return
	integration_accumulator += delta
	while integration_accumulator + 0.000000001 >= BoulderController.FIXED_DT:
		integration_accumulator -= BoulderController.FIXED_DT
		var before_distance: float = boulder.distance
		var before_state: String = boulder.state
		var before_falls: int = boulder.partial_falls
		boulder.advance(BoulderController.FIXED_DT, command[0], command[1], command[2])
		advance_character_motion(before_distance, before_state, before_falls)
		update_progression()
		best = mastery.highest_distance
		if boulder.state == "result" and last_state != "result":
			falls_seen += 1
			_save_progression()
		if boulder.state == "summit" and prestige_phase.is_empty():
			_start_prestige()
		last_state = boulder.state
		if paused or persistence_failed or save_blocked or not prestige_phase.is_empty():
			integration_accumulator = 0.0
			break

func update_progression() -> int:
	if save_blocked or persistence_failed: return 0
	var earned: int = mastery.award_distance(boulder.peak,mountain.total_length)
	best = mastery.highest_distance
	if boulder.state != "summit" and modal_milestone.is_empty():
		var milestone: Dictionary = mastery.consume_pending_milestone()
		if not milestone.is_empty() and int(milestone.distance) < 1000:
			modal_milestone = milestone
			paused = true
			_open_board(true)
	if earned > 0: _save_progression()
	return earned

func _process(delta: float) -> void:
	super._process(delta)
	if persistence_failed:
		if ui_layer != null and ui_mode != "storage_error": _storage_error()
		return
	if screen == "game" and not prestige_phase.is_empty() and not save_blocked:
		phase_elapsed += delta
		if rolling_stone != null and is_instance_valid(rolling_stone) and prestige_phase == "BOULDER_ROLLS_AWAY":
			rolling_stone.position.x = 750.0 + minf(phase_elapsed,1.0)*560.0
			rolling_stone.rotation = phase_elapsed*1.5
		if phase_elapsed >= (1.2 if mastery.prestige_count == 0 else 0.55):
			_advance_prestige()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if persistence_failed: return
		if event.keycode == KEY_M:
			preferences.muted = not bool(preferences.muted)
			_apply_preferences()
			_save_progression()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F11:
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
		if not prestige_phase.is_empty(): return
		if event.keycode == KEY_ESCAPE:
			if ui_mode == "board": _close_board()
			elif ui_mode != "": _dismiss_overlay()
			elif screen == "game": _pause_menu()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_TAB and screen == "game" and ui_mode.is_empty():
			_open_board(false)
			get_viewport().set_input_as_handled()
			return
	if ui_mode.is_empty() and screen == "game": super._unhandled_input(event)

func _menu_action(action: String) -> void:
	if transition_busy or persistence_failed: return
	if not prestige_phase.is_empty() and action != "continue": return
	match action:
		"continue": _begin()
		"new_game": _confirmation("새로운 등반", "이 MVP의 EXP·숙련·프레스티지 기록을 초기화합니다. 기존 정식 저장은 변경하지 않습니다.", _reset_game)
		"mastery": _open_board(false)
		"sephirot": _sephirot()
		"settings": _settings()
		"help": _help()

func _show_title() -> void:
	screen = "title"
	paused = false
	ui_mode = ""
	board.hide()
	_clear_overlay()
	menu.show()
	menu.refresh(mastery, has_resume and not save_blocked)
	if save_blocked:
		ui_mode = "invalid_save"
		var area: Control = _new_overlay("기록을 불러오지 못했습니다",save_error+"\n새로운 등반을 선택하면 원본을 백업한 뒤 시작합니다.")
		UI.button(area,"메인 화면으로",Rect2(420,760,500,85),func():
			_clear_overlay()
			ui_mode = ""
			paused = false).grab_focus()

func _begin() -> void:
	if save_blocked or not has_resume: return
	menu.hide()
	board.hide()
	_clear_overlay()
	screen = "game"
	paused = false
	ui_mode = ""
	if not prestige_phase.is_empty():
		paused = true
		_present_prestige()
	elif not modal_milestone.is_empty(): _open_board(true)
	else: update_progression()

func _reset_game() -> void:
	if transition_busy or persistence_failed: return
	transition_busy = true
	if not _backup_existing(save_path):
		transition_busy = false
		return
	mastery = Mastery.new()
	mastery.begin_run()
	run_number = 1
	falls_seen = 0
	best = 0
	previous_best = 0
	prestige_phase = ""
	modal_milestone = {}
	save_blocked = false
	persistence_failed = false
	save_error = ""
	_install_world(_fresh_world())
	last_state = "climbing"
	has_resume = true
	camera_position = mountain.sample(0)
	_save_progression()
	_begin()
	transition_busy = false

func _new_run() -> void:
	if save_blocked or persistence_failed or not prestige_phase.is_empty() or boulder.state != "result": return
	_start_new_cycle_run()

func _start_new_cycle_run() -> void:
	previous_best = mastery.highest_distance
	run_number += 1
	mastery.begin_run()
	modal_milestone = {}
	_install_world(_fresh_world())
	last_state = "climbing"
	integration_accumulator = 0
	camera_position = mountain.sample(0)
	has_resume = true
	paused = false
	screen = "game"
	ui_mode = ""
	board.hide()
	menu.hide()
	_clear_overlay()
	_save_progression()

func _open_board(milestone: bool) -> void:
	if board == null or persistence_failed: return
	board_return = screen
	ui_mode = "board"
	paused = true
	menu.hide()
	_clear_overlay()
	board.show()
	board.refresh(mastery, not save_blocked and (milestone or (screen=="game" and _safe_for_upgrade())), "%dm · 새로운 숙련이 열렸습니다" % int(modal_milestone.distance) if milestone else "숙련의 석판")
	board.slots[board.selection].grab_focus()

func _close_board() -> void:
	if persistence_failed: return
	board.hide()
	modal_milestone = {}
	ui_mode = ""
	paused = false
	_save_progression()
	if board_return == "title": _show_title()
	else: update_progression()

func _confirm_purchase(id: String) -> void:
	if persistence_failed or not board.purchase_allowed or not mastery.can_purchase_node(id): return
	var node: Dictionary = mastery.get_node_definition(id)
	_confirmation("숙련 각인", "%s\n%d EXP를 사용합니다." % [node.name,node.exp_cost], func(): _purchase(id))

func _purchase(id: String) -> void:
	var safe: bool = not modal_milestone.is_empty() or (screen=="game" and _safe_for_upgrade())
	if not safe or save_blocked or persistence_failed or not mastery.purchase_node(id): return
	boulder.apply_mastery_effects(mastery.get_mastery_modifiers())
	_save_progression()
	_clear_overlay()
	_open_board(not modal_milestone.is_empty())

func _new_overlay(title: String, body: String = "") -> Control:
	_clear_overlay()
	paused = true
	overlay = Canvas.new()
	ui_layer.add_child(overlay)
	UI.backdrop(overlay.canvas,Rect2(0,0,1920,1080),Color(0.01,0.02,0.02,0.92))
	UI.label(overlay.canvas,title,Rect2(420,170,1100,90),48,UI.GOLD)
	var text: Label = UI.label(overlay.canvas,body,Rect2(420,300,1080,370),30)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return overlay.canvas

func _clear_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		overlay.hide()
		overlay.queue_free()
	overlay = null
	rolling_stone = null

func _confirmation(title: String, body: String, callback: Callable) -> void:
	var area: Control = _new_overlay(title,body)
	ui_mode = "confirm_board" if board.visible else "confirm"
	UI.button(area,"확인",Rect2(420,760,400,85),callback,true).grab_focus()
	UI.button(area,"취소",Rect2(920,760,400,85),_dismiss_overlay)

func _dismiss_overlay() -> void:
	_clear_overlay()
	if board.visible:
		ui_mode = "board"
		paused = true
	elif screen=="title": _show_title()
	else:
		ui_mode = ""
		paused = false

func _pause_menu() -> void:
	ui_mode = "pause"
	var area: Control = _new_overlay("잠시 돌을 내려놓고", "지금의 위치와 속도는 그대로 기다립니다.")
	UI.button(area,"계속 등반",Rect2(420,630,440,85),_dismiss_overlay,true).grab_focus()
	UI.button(area,"숙련의 석판",Rect2(920,630,440,85),func(): _open_board(false))
	UI.button(area,"저장하고 처음 화면",Rect2(420,750,440,85),func():
		if _save_progression(): _show_title())
	UI.button(area,"설정",Rect2(920,750,440,85),_settings)

func _settings() -> void:
	ui_mode = "settings"
	var area: Control = _new_overlay("설정", "사운드 · 화면 · 조작")
	UI.button(area,"음소거: "+("켜짐" if sound.muted else "꺼짐"),Rect2(420,425,450,85),func():
		preferences.muted = not bool(preferences.muted)
		_apply_preferences()
		_save_progression()
		_settings())
	var slider := HSlider.new()
	slider.position = Vector2(950,450)
	slider.size = Vector2(470,50)
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.value = preferences.volume
	area.add_child(slider)
	slider.value_changed.connect(func(v: float): preferences.volume=v; _apply_preferences())
	slider.drag_ended.connect(func(_changed: bool): _save_progression())
	UI.button(area,"전체 화면 전환",Rect2(420,550,450,85),_toggle_fullscreen)
	UI.label(area,"D / → 밀기 · Shift 힘주기\nSpace 버티기 · Tab 석판 · Esc 메뉴",Rect2(420,660,1000,100),28)
	UI.button(area,"돌아가기",Rect2(420,820,450,85),_dismiss_overlay).grab_focus()

func _toggle_fullscreen() -> void:
	preferences.fullscreen = DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if preferences.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	_save_progression()

func _apply_preferences() -> void:
	sound.muted = bool(preferences.muted)
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(0.001,float(preferences.volume))))

func _help() -> void:
	ui_mode = "help"
	var area: Control = _new_overlay("돌을 밀어 올리는 법", "D / → 밀기 · Shift 힘주기 · Space 버티기\n경사에서는 일반 밀기도 Slip 위험이 쌓입니다.\n밀기 키를 잠시 놓고, 후퇴하면 Space로 제동하세요.\n진흙은 체력, 자갈과 젖은 바위는 발판에 주의하세요.\n쉼터에서 손을 놓으면 체력과 자세를 회복합니다.\nTab 석판 · 첫 해금과 정지한 쉼터에서 구매\nEsc 메뉴 · EXP와 숙련은 일반 추락 후에도 남습니다.")
	UI.button(area,"돌아가기",Rect2(420,820,440,85),_dismiss_overlay).grab_focus()
	if FileAccess.file_exists("user://sisyphus-v1.json") and mastery.historical_exp_earned == 0 and mastery.highest_distance == 0:
		UI.button(area,"이전 최고 기록 가져오기",Rect2(930,820,540,85),func(): _confirmation("이전 기록 가져오기", "정식 저장은 백업 후 그대로 보존합니다. 최고 거리와 일반 숙련 구매 자격만 가져오며, 기존 레벨·EXP·강화는 변환하지 않습니다.",_import_legacy))

func _import_legacy() -> void:
	if persistence_failed or save_blocked: return
	var source: String = FileAccess.get_file_as_string("user://sisyphus-v1.json")
	var old: Variant = JSON.parse_string(source)
	if not old is Dictionary or not old.get("best") is float and not old.get("best") is int: return
	if not _backup_existing("user://sisyphus-v1.json"): return
	if not mastery.import_legacy_record(float(old.best)): return
	best = mastery.highest_distance
	_save_progression()
	_show_title()

func _backup_existing(source_path: String) -> bool:
	if not FileAccess.file_exists(source_path): return true
	var backup: String = source_path+".backup-"+str(Time.get_unix_time_from_system()).replace(".","-")
	var copied: bool = DirAccess.copy_absolute(ProjectSettings.globalize_path(source_path),ProjectSettings.globalize_path(backup)) == OK
	if not copied:
		save_error = "이전 저장을 백업하지 못했습니다. 기존 진행은 그대로 보존됩니다."
		var area: Control = _new_overlay("백업 실패",save_error)
		ui_mode = "backup_error"
		UI.button(area,"돌아가기",Rect2(420,760,500,85),_dismiss_overlay).grab_focus()
	return copied

func _sephirot() -> void:
	if not mastery.sephirot_unlocked: return
	ui_mode = "sephirot"
	var area: Control = _new_overlay("운명의 직조", "말쿠트 · 왕국\n\n발이 닿는 대지에 첫 실이 걸렸습니다.\nEXP 획득량 ×5 · 영구 활성\n\n운명의 실 %d개\n다른 세피라는 아직 구매할 수 없습니다." % mastery.threads_balance)
	UI.image(area,"node_core",Rect2(1300,300,240,240))
	UI.button(area,"돌아가기",Rect2(420,820,450,85),_dismiss_overlay).grab_focus()

func _start_prestige() -> void:
	if not prestige_phase.is_empty(): return
	prestige_phase = "SUMMIT_REACHED"
	phase_elapsed = 0
	modal_milestone = {}
	paused = true
	_save_progression()
	_present_prestige()

func _present_prestige() -> void:
	ui_mode = "prestige"
	var captions: Dictionary = {"SUMMIT_REACHED":"마침내, 정상", "FIRST_SUMMIT_SEQUENCE":"끝에 닿은 손이 돌을 놓는다.","BOULDER_ROLLS_AWAY":"돌은 다시 아래로 굴러간다.","PRESTIGE_COMMIT":"숙련은 지워져도, 기억은 남는다.","SEPHIROT_REVEAL":"운명의 직조가 모습을 드러낸다.","MALKUTH_UNLOCK":"말쿠트 · 대지에 새겨진 첫 실", "NEW_RUN":"다시, 첫 발을 내딛는다."}
	var area: Control = _new_overlay(str(captions.get(prestige_phase,"")),"EXP와 구매한 숙련은 초기화됩니다.\n개방한 구매 자격과 운명의 실은 영구히 남습니다." if not mastery.first_summit_completed else "말쿠트 활성 · 다음 등반부터 EXP ×5\n특별 숙련의 구매 자격이 열렸습니다.")
	rolling_stone = UI.image(area,"boulder",Rect2(750,680,180,180))

func _advance_prestige() -> void:
	if persistence_failed: return
	var index: int = PRESTIGE_PHASES.find(prestige_phase)
	if index < 0: return
	if prestige_phase == "PRESTIGE_COMMIT":
		# Saving the committed profile and journal phase together is the durable boundary.
		if mastery.commit_prestige(mastery.current_run_token):
			var summit_state: Dictionary = boulder.snapshot()
			summit_state.erase("mastery_run")
			_install_world(mountain)
			boulder.restore(summit_state)
		if not _save_progression(): return
	if prestige_phase == "NEW_RUN":
		prestige_phase = ""
		phase_elapsed = 0
		_start_new_cycle_run()
		return
	prestige_phase = PRESTIGE_PHASES[index+1]
	phase_elapsed = 0
	if not _save_progression(): return
	_present_prestige()

func _save_payload() -> Dictionary:
	save_revision += 1
	if boulder is MasteryBoulder:
		mastery.run_ability_charges = boulder.get_run_ability_charges()
		mastery.run_ability_cooldowns = boulder.get_run_ability_cooldowns()
	return {"version":5,"save_version":1,"revision":save_revision,"saved_at_unix_msec":Time.get_unix_time_from_system()*1000.0,"world":mountain.snapshot(),"run":boulder.snapshot(),"mastery":mastery.snapshot(),"run_number":run_number,"falls_seen":falls_seen,"previous_best":previous_best,"prestige_phase":prestige_phase,"phase_elapsed":phase_elapsed,"modal_milestone":modal_milestone.duplicate(true),"settings":preferences.duplicate()}

func _write_save_file(payload: Dictionary) -> Error:
	return super._write_save_file(payload) if SaveContract.validate(payload) else ERR_INVALID_DATA

func _save_progression() -> bool:
	return _persist_snapshot()

func _save_for_web() -> bool:
	return _persist_snapshot()

func _persist_snapshot() -> bool:
	if save_blocked: return false
	var payload: Dictionary = _save_payload()
	if not SaveContract.validate(payload):
		persistence_failed = true
		save_error = "저장 상태 검증에 실패했습니다. 기존 저장은 보존됩니다."
		return false
	var result: Error = _write_save_file(payload)
	var mirrored: bool = _write_web_mirror(JSON.stringify(payload)) if web_mode else false
	var success: bool = (mirrored or (result == OK and _web_userfs_persistent())) if web_mode else result == OK
	persistence_failed = not success
	save_error = "" if success else "저장하지 못했습니다. 진행을 멈추고 현재 상태를 보존하고 있습니다."
	if success: has_resume = true
	web_save_elapsed = 0
	return success

func _storage_error() -> void:
	ui_mode = "storage_error"
	var area: Control = _new_overlay("저장 공간을 확인해 주세요",save_error+"\n창을 닫기 전에 다시 저장해 주세요.")
	UI.button(area,"저장 다시 시도",Rect2(420,760,500,85),func():
		if _persist_snapshot():
			if not prestige_phase.is_empty(): _present_prestige()
			else: _dismiss_overlay(),true).grab_focus()

func _load_save() -> void:
	var source: String = FileAccess.get_file_as_string(save_path) if FileAccess.file_exists(save_path) else ""
	var candidates: Array = []
	if not source.is_empty(): candidates.append(JSON.parse_string(source))
	if web_mode:
		var mirror: Dictionary = _read_web_mirror()
		if not str(mirror.get("data","")).is_empty(): candidates.append(JSON.parse_string(mirror.data))
	var selected: Dictionary = {}
	for candidate: Variant in candidates:
		if candidate is Dictionary and SaveContract.validate(candidate):
			if selected.is_empty() or int(candidate.revision)>int(selected.revision): selected=candidate
	if selected.is_empty():
		if not candidates.is_empty():
			save_blocked = true
			save_error = "저장을 복원하지 못했습니다. 원본을 보존했습니다."
		return
	mastery.restore(selected.mastery)
	_install_world(Mountain.from_snapshot(selected.world))
	boulder.restore(selected.run)
	run_number = int(selected.run_number)
	falls_seen = int(selected.falls_seen)
	previous_best = float(selected.previous_best)
	best = mastery.highest_distance
	prestige_phase = selected.prestige_phase
	phase_elapsed = float(selected.phase_elapsed)
	modal_milestone = selected.modal_milestone.duplicate(true)
	preferences = selected.settings.duplicate()
	save_revision = int(selected.revision)
	last_state = boulder.state
	has_resume = true

func _web_storage_key_expression() -> String:
	return "'sisyphus:mastery-mvp:v1:' + new window.URL('.', window.location.href).pathname + ':' + "+JSON.stringify(save_path)

func _draw_title(_size: Vector2) -> void: pass
func _draw_pause(_size: Vector2) -> void: pass
func _draw_summit(_size: Vector2) -> void: pass

func ahead_information() -> Dictionary:
	if "SPC01" not in mastery.get_mastery_modifiers().purchased_nodes: return {}
	var end: float = minf(mountain.total_length-0.01,boulder.distance+50)
	var low: float = INF
	var high: float = -INF
	var surfaces: Array[String] = []
	for sample_index: int in range(51):
		var at: float = lerpf(boulder.distance,end,float(sample_index)/50.0)
		var angle: float = rad_to_deg(mountain.angle_at(at))
		low = minf(low,angle)
		high = maxf(high,angle)
		var surface: String = str(mountain.surface_at(at).id)
		if surface not in surfaces: surfaces.append(surface)
	var ledge_count: int = 0
	for ledge: Dictionary in mountain.ledges:
		if float(ledge.distance)>boulder.distance and float(ledge.distance)<=end: ledge_count+=1
	return {"angle_min":low,"angle_max":high,"surfaces":surfaces,"ledges":ledge_count}

func slip_warning_active() -> bool:
	return "SPC03" in mastery.get_mastery_modifiers().purchased_nodes and boulder.slip>=60

func _slip_recovery_hint() -> String:
	return "발밑이 불안합니다 · 밀기 키를 놓고 자세를 회복하세요"

func _draw_progression_hud(size: Vector2) -> void:
	if boulder.has_method("environment_info"):
		var environment: Dictionary = boulder.call("environment_info")
		if bool(environment.get("enabled",false)):
			_text(str(environment.get("note","")),Vector2(56,201),18,GOLD)
	_text("%d EXP  ·  숙련 %d/35  ·  Tab 석판" % [mastery.available_exp,mastery.purchased_mastery_nodes.size()],Vector2(40,size.y-55),24,GOLD)
	var ahead: Dictionary = ahead_information()
	if not ahead.is_empty():
		_text("앞길 50m · %.0f~%.0f° · %s · 돌턱 %d" % [ahead.angle_min,ahead.angle_max,"/".join(ahead.surfaces),ahead.ledges],Vector2(40,size.y-95),22,MUTED)
	if slip_warning_active():
		_center("발밑이 흔들립니다 · 밀기 키를 놓고 자세를 잡으세요",150,28,RED)
