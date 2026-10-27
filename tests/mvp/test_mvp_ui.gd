extends SceneTree

const Profile = preload("res://scripts/mastery_progression.gd")
const Board = preload("res://scenes/mvp/mastery_board.tscn")
const Menu = preload("res://scenes/mvp/main_menu.tscn")
const UI = preload("res://scripts/mvp/ui_theme.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func run() -> void:
	var profile = Profile.new()
	profile.begin_run("ui-test")
	var board = Board.instantiate()
	var board_viewport := SubViewport.new()
	board_viewport.size = Vector2i(1920,1080)
	root.add_child(board_viewport)
	board_viewport.add_child(board)
	board.refresh(profile,false)
	check(board.slots.size()==35,"all35slots")
	check(board.connection_layer.get_parent()==board.canvas,"connectionlayerusesdesigncoordinates")
	check(board.connection_layer.get_index()>0,"connectionsabovebackdrop")
	check(board.connection_layer.mouse_filter==Control.MOUSE_FILTER_IGNORE,"connectionsdonotinterceptinput")
	check(board.connection_segments.size()==27,"all27prerequisiteconnections")
	for node: Dictionary in profile.definitions:
		check(board.slots.has(node.id),"slotid "+node.id)
		check(board.slots[node.id].node_id==node.id,"definitionbinding "+node.id)
		check(Rect2(Vector2.ZERO,Vector2(1920,1080)).encloses(board.slots[node.id].get_rect()),"bounded "+node.id)
		check(board.connection_layer.get_index()<board.slots[node.id].get_index(),"connectionsbelowslot "+node.id)
	var mapping=FileAccess.open("res://docs/mvp/mastery-slots.csv",FileAccess.READ)
	check(mapping!=null,"slotmappingexists")
	var mapped: int = 0
	if mapping!=null:
		var headers: PackedStringArray = mapping.get_csv_line()
		check(headers[0]=="node_id","slotmappingheader")
		while not mapping.eof_reached():
			var cells: PackedStringArray = mapping.get_csv_line()
			if cells.size()<8: continue
			var id: String = cells[0]
			var actual: Rect2 = board.slots[id].get_rect()
			check(actual==Rect2(float(cells[3]),float(cells[4]),float(cells[5]),float(cells[6])),"csvrect "+id)
			check(cells[7]==";".join(profile.get_node_definition(id).prerequisites),"csvprerequisites "+id)
			mapped+=1
		check(mapped==35,"csv35rows")
	check(board.buy.disabled,"readonlyblocks")
	profile.award_distance(250,1000)
	board.refresh(profile,true)
	board.select_node("STR01")
	check(board.slots.STR01._pulse!=null,"newlyavailablepulse")
	check(not board.buy.disabled,"firstunlockpurchase")
	check(profile.purchase_node("STR01"),"purchasefirst")
	board.refresh(profile,true)
	check(board.slots.STR01.state_name=="purchased","ownedreflects")
	check(board.buy.disabled,"duplicatebuttondisabled")
	check(board.slots.STR02.state_name=="available","nextnodeavailable")
	check(board.slots.END01.state_name=="available","crossbranchfree")
	var purchase_pulse: Tween = board.slots.STR01._pulse
	board.refresh(profile,true)
	check(board.slots.STR01._pulse==purchase_pulse,"refreshdoesnotstackpulse")
	# Tween processing happens after the nodes in a frame. A separate .35s
	# timer can win that ordering under load; observe completion itself instead.
	var pulse_done: Array[bool] = [false]
	purchase_pulse.finished.connect(func(): pulse_done[0] = true, CONNECT_ONE_SHOT)
	var pulse_deadline: int = Time.get_ticks_msec() + 10000
	while not pulse_done[0] and Time.get_ticks_msec() < pulse_deadline:
		await process_frame
	check(pulse_done[0] and board.slots.STR01.modulate.is_equal_approx(Color.WHITE),"pulsefinishesandrestoreswhitewithinboundedwait")
	for dimensions: Vector2 in [Vector2(1920,1080),Vector2(1280,720),Vector2(960,540)]:
		board_viewport.size=Vector2i(dimensions)
		await process_frame
		check(board.size==dimensions,"boardfollowsviewport")
		check(is_equal_approx(board.canvas.scale.x,dimensions.x/1920.0),"responsive")
	var menu = Menu.instantiate()
	root.add_child(menu)
	menu.refresh(profile,false)
	for text: Label in [menu.record,menu.wallet,menu.history]:
		check(text.position.x==1540 and text.size.x==240,"rightpaneltextinset")
	check(menu.controls.continue.disabled,"continueusesdata")
	check(not menu.controls.sephirot.visible,"sephirotprivate")
	check(not menu.history.text.contains("1000"),"summitdistancehidden")
	profile.award_distance(1000,1000)
	profile.commit_prestige("ui-test")
	menu.refresh(profile,true)
	check(not menu.controls.continue.disabled,"continueenabled")
	check(menu.controls.sephirot.visible,"sephirotrevealed")
	check(menu.history.text.contains("×5"),"malkuthdisplay")
	check(menu.history.text.contains("1회"),"prestigedisplay")
	for id: String in UI.catalog: check(UI.texture(id)!=null,"asset "+id)
	check(UI.textures.size()<=20,"boundedassetloading")
	board_viewport.queue_free()
	menu.queue_free()
	await process_frame
	var output = {"checks":checks,"failures":failures,"resolutions":["1920x1080","1280x720","960x540"],"scope":"Control/data binding and layout bounds; rendered browser inspection is separate"}
	var file=FileAccess.open("res://tests/mvp/results/ui-components.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"\t"))
	print("MVP UI ",checks," checks ",failures.size()," failures")
	for message: String in failures: printerr(message)
	quit(0 if failures.is_empty() else 1)
