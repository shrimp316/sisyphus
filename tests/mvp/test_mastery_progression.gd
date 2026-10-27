extends SceneTree
const Mastery = preload("res://scripts/mastery_progression.gd")
var checks: int = 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	var p = Mastery.new()
	check(p.definitions.size() == 35, "35 definitions")
	var costs: int = 0
	var ids: Dictionary = {}
	for node: Dictionary in p.definitions:
		check(not ids.has(node.id), "unique " + str(node.id))
		ids[node.id] = true
		if node.category != "SPC":
			costs += int(node.exp_cost)
	check(costs == 3840, "30 normal nodes cost 3840")
	p.begin_run("run-one")
	check(p.award_distance(149.9, 1000) == 60, "two first EXP milestones")
	check(p.permanent_mastery_unlocks.is_empty(), "no premature eligibility")
	check(p.award_distance(150, 1000) == 30, "third EXP milestone")
	check(p.get_new_unlocks().size() == 10, "first ten unlocks")
	check(p.consume_pending_milestone().distance == 150, "150 popup queued")
	check(p.consume_pending_milestone().is_empty(), "popup consumed once")
	check(p.award_distance(250, 1000) == 60, "unchanged EXP for fourth and fifth milestones")
	check(p.award_distance(250, 1000) == 0, "no repeat EXP")
	check(not p.purchase_node("STR02"), "prerequisite enforced")
	check(p.purchase_node("STR01"), "first purchase")
	check(p.available_exp == 120, "wallet debited")
	check(not p.purchase_node("STR01"), "duplicate purchase rejected")
	check(p.purchase_node("STR02"), "sequential purchase")
	check(p.purchase_node("STR03"), "third purchase")
	check(not p.purchase_node("STR04"), "insufficient EXP rejected")
	check(is_equal_approx(p.get_mastery_modifiers().effects.push_bonus, .06), "additive push recalculation")
	check(p.get_mastery_modifiers() == p.get_mastery_modifiers(), "modifiers idempotent")
	p.set_feature_enabled("STR01", false)
	check(is_equal_approx(p.get_mastery_modifiers().effects.push_bonus, .03), "disabled purchased effect is absent")
	p.set_feature_enabled("STR01", true)
	check(is_equal_approx(p.get_mastery_modifiers().effects.push_bonus, .06), "re-enabled effect is recalculated")
	p.run_ability_charges = {"BRE10_used": true}
	p.run_ability_cooldowns = {"STR10": 1.0}
	p.begin_run("run-two")
	check(p.run_ability_charges.is_empty() and p.run_ability_cooldowns.is_empty(), "new run resets one-shot state")
	check(p.available_exp == 30 and p.purchased_mastery_nodes.size() == 3, "fall preserves wallet and nodes")
	check(p.award_distance(250, 1000) == 100, "repeat run only base reward")
	check(p.consume_pending_milestone().is_empty(), "permanent unlock does not pause repeat run")
	check(p.award_distance(500, 1000) == 150, "record reward for new distances")
	check(p.permanent_mastery_unlocks.size() == 20, "500 unlock count")
	check(p.award_distance(750, 1000) == 150, "750 EXP")
	check(p.permanent_mastery_unlocks.size() == 30, "750 unlock count")
	check(not p.commit_prestige("run-two"), "cannot prestige below summit")
	check(p.award_distance(1000, 1000) == 150, "first summit reward before multiplier")
	check(p.permanent_mastery_unlocks.size() == 35, "special eligibility")
	p.set_feature_enabled("SPC01", true)
	check(not p.can_purchase_node("SPC01"), "special waits until prestige")
	check(not p.commit_prestige("other-run"), "wrong token rejected")
	check(p.commit_prestige("run-two"), "first prestige")
	check(p.available_exp == 0 and p.cycle_exp_earned == 0 and p.purchased_mastery_nodes.is_empty(), "cycle reset")
	check(p.historical_exp_earned == 700 and p.permanent_mastery_unlocks.size() == 35, "history persists")
	check(p.exp_multiplier() == 5 and p.threads_balance == 1 and p.prestige_count == 1, "Malkuth and thread")
	check(not p.commit_prestige("run-two"), "prestige retry idempotent")
	p.begin_run("run-three")
	check(p.award_distance(1000, 1000) == 2000, "known 1000m pays exactly 2000")
	check(p.purchase_node("SPC01"), "special purchase in next cycle")
	p.set_feature_enabled("SPC02", false)
	check(p.get_node_state("SPC02") == "disabled", "explicitly disabled special cannot be purchased")
	check(p.commit_prestige("run-three"), "second prestige")
	check(p.exp_multiplier() == 5 and p.threads_balance == 2, "multiplier never stacks")
	p.begin_run("run-four")
	check(p.award_distance(50, 1000) == 100, "x5 not x25")
	check(p.award_distance(NAN, 1000) == 0 and p.award_distance(100, INF) == 0, "nonfinite ignored")
	var full = Mastery.new()
	full.begin_run("all-nodes")
	full.award_distance(1000, 1000)
	for index: int in range(9):
		full.begin_run("funding-" + str(index))
		full.award_distance(1000, 1000)
	for node: Dictionary in full.definitions:
		if node.category != "SPC":
			check(full.purchase_node(node.id), "normal sequence purchase " + str(node.id))
	var modifiers: Dictionary = full.get_mastery_modifiers().effects
	check(is_equal_approx(modifiers.push_bonus, .15), "complete strength adds 15 percent")
	check(is_equal_approx(modifiers.capacity_bonus, .20), "complete endurance adds 20 percent")
	check(is_equal_approx(modifiers.steep_stationary_recovery, 1.5), "BRE09 replaces rate instead of stacking")
	print(JSON.stringify({"suite": "mastery_progression", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
