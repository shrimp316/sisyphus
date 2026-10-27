extends SceneTree

const SCENE: PackedScene = preload("res://scenes/mvp/main_mvp.tscn")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: ", label)

func label_with_text(node: Node, value: String) -> Label:
	if node is Label and node.text == value: return node
	for child: Node in node.get_children():
		var found: Label = label_with_text(child,value)
		if found != null: return found
	return null

func has_role(node: Node, text: String, variation: StringName) -> bool:
	var label: Label = label_with_text(node,text)
	return label != null and label.theme_type_variation == variation

func run() -> void:
	var main = SCENE.instantiate()
	main.save_path = "user://typography-presentation-fixture-%d.json" % Time.get_ticks_usec()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	await process_frame
	main.mastery.first_summit_completed = true
	main.mastery.prestige_count = 1
	main.prestige_phase = "MALKUTH_UNLOCK"
	main._present_prestige()
	check(has_role(main.overlay,"운명의 직조",&"SisyphusTitleLabel"), "first unlock title")
	check(has_role(main.overlay,"MALKUTH — 왕국",&"SisyphusSectionLabel"), "first unlock name")
	check(has_role(main.overlay,"첫 번째 실이 이어졌다.",&"SisyphusNarrativeLabel"), "first unlock narrative")
	check(has_role(main.overlay,"EXP 획득량 ×5",&"SisyphusHUDLabel"), "first unlock multiplier")
	main.mastery.prestige_count = 2
	main._present_prestige()
	check(label_with_text(main.overlay,"첫 번째 실이 이어졌다.") == null, "repeat prestige does not claim first unlock")
	main.mastery.sephirot_unlocked = true
	main._sephirot()
	check(has_role(main.overlay,"운명의 직조",&"SisyphusTitleLabel"), "sephirot title")
	check(has_role(main.overlay,"MALKUTH — 왕국",&"SisyphusSectionLabel"), "sephirot name")
	check(has_role(main.overlay,"EXP 획득량 ×5 · 영구 활성",&"SisyphusHUDLabel"), "sephirot multiplier")
	main.free()
	print(JSON.stringify({"suite":"typography_presentation","checks":checks,"failures":failures,"scope":"actual scene with artificial profile, no progression or save writes"}))
	quit(0 if failures.is_empty() else 1)
