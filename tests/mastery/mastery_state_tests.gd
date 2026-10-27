extends SceneTree
const Loader = preload("res://scripts/mastery/mastery_layout_loader.gd")
const Resolver = preload("res://scripts/mastery/mastery_state_resolver.gd")
const Adapter = preload("res://scripts/mastery/mastery_progress_adapter.gd")
const Report = preload("res://tests/mastery/test_report.gd")
var report = Report.new()
var nodes: Array = []
var node_by_id: Dictionary = {}
var recursive_purchase_result: bool = true

func _initialize() -> void:
	call_deferred("run")

func count_eligible(snapshot: Dictionary) -> int:
	var count: int = 0
	for node: Dictionary in nodes:
		if Resolver.resolve(node, snapshot).eligible: count += 1
	return count

func run() -> void:
	nodes = Loader.load_nodes()
	for node: Dictionary in nodes: node_by_id[node.node_id] = node
	var adapter = Adapter.new()
	var cases: Array = [["zero", [0,0,0,0], 0], ["250", [4,3,3,0], 150], ["500", [7,7,6,0], 300], ["750", [10,10,10,0], 450], ["first_summit", [10,10,10,0], 600], ["next_run", [10,10,10,5], 600]]
	var fixture_results: Array = []
	for test_case: Array in cases:
		adapter.apply_fixture(test_case[0])
		var snapshot: Dictionary = adapter.snapshot()
		var counts: Dictionary = {"strength":0,"endurance":0,"breath":0,"special":0}
		var bought: int = 0
		for node: Dictionary in nodes:
			var state: Dictionary = Resolver.resolve(node, snapshot, node.node_id)
			if state.eligible: counts[node.track] += 1
			if state.purchased: bought += 1
			report.check(state.selected, "selection independent of base state %s %s" % [test_case[0], node.node_id])
			report.check(Resolver.resolve(node, snapshot).base_state == state.base_state, "selection does not replace base state %s %s" % [test_case[0], node.node_id])
			if node.track == "special":
				report.check(not state.can_purchase and not adapter.purchase(node), "undefined special never purchases " + str(test_case[0]))
		var expected: Array = test_case[1]
		report.check(counts.values() == expected, "milestone distribution " + str(test_case[0]))
		report.check(bought == 0, "eligibility is not purchased " + str(test_case[0]))
		report.check(snapshot.total_xp == test_case[2], "actual first-run XP fixture " + str(test_case[0]))
		fixture_results.append({"fixture": test_case[0], "eligible": counts, "purchased": bought, "total_xp": snapshot.total_xp})
		adapter.record_reach(int(snapshot.current_distance))
		report.check(adapter.snapshot().total_xp == snapshot.total_xp, "revisiting fixture distance does not duplicate XP " + str(test_case[0]))
	adapter.apply_fixture("250")
	var first: Dictionary = node_by_id.act1_strength_01
	var second: Dictionary = node_by_id.act1_strength_02
	report.check(Resolver.resolve(first, adapter.snapshot()).base_state == "AVAILABLE", "first eligible strength available")
	report.check(Resolver.resolve(second, adapter.snapshot()).base_state == "LOCKED", "eligible successor requires previous rank")
	var before: Dictionary = adapter.snapshot()
	report.check(not adapter.purchase(second) and adapter.snapshot() == before, "out-of-order purchase refuses atomically")
	report.check(adapter.purchase(first), "first real pending point purchases")
	report.check(adapter.snapshot().total_xp == before.total_xp and adapter.snapshot().pending_points == before.pending_points - 1, "purchase consumes one point, does not subtract XP")
	before = adapter.snapshot()
	report.check(not adapter.purchase(first) and adapter.snapshot() == before, "same node cannot be purchased twice")
	report.check(Resolver.resolve(second, adapter.snapshot()).base_state == "AVAILABLE", "successor available after prerequisite purchase")
	report.check(adapter.purchase(second), "second point purchases")
	var breath: Dictionary = node_by_id.act1_breath_01
	report.check(Resolver.resolve(breath, adapter.snapshot()).base_state == "INSUFFICIENT_EXP", "zero pending points displayed as legacy insufficient state")
	before = adapter.snapshot()
	report.check(not adapter.purchase(breath) and adapter.snapshot() == before, "unfunded purchase changes nothing")
	var contradictory: Dictionary = adapter.snapshot()
	contradictory.first_reach_flags = {"250":false,"500":false,"750":false}
	contradictory.best = 0
	contradictory.current_distance = 0
	report.check(Resolver.resolve(first, contradictory).base_state == "PURCHASED", "existing saved rank takes precedence over distance lock")
	var detached: Dictionary = adapter.snapshot()
	detached.ranks.strength = 10
	detached.first_reach_flags["750"] = true
	report.check(adapter.snapshot().ranks.strength == 2 and not adapter.snapshot().first_reach_flags["750"], "snapshot mutation cannot alter adapter ranks or flags")
	adapter.fund_preview()
	report.check(adapter.purchase(breath) and adapter.snapshot().ranks.recovery == 1 and not adapter.snapshot().ranks.has("breath"), "breath maps to current recovery rank")
	adapter.apply_fixture("zero")
	adapter.record_reach(749)
	report.check(count_eligible(adapter.snapshot()) == 20, "749m does not prematurely unlock 750 milestone")
	adapter.record_reach(750)
	adapter.record_reach(0)
	report.check(count_eligible(adapter.snapshot()) == 30, "backtracking does not relock first-reach milestones")
	adapter.record_reach(1000)
	var summit_run: int = int(adapter.snapshot().first_summit_run_number)
	report.check(summit_run == 1 and count_eligible(adapter.snapshot()) == 30, "first summit records eligibility without special unlock")
	adapter.begin_next_run()
	report.check(count_eligible(adapter.snapshot()) == 35 and adapter.snapshot().current_distance == 0, "next run opens special eligibility at zero current distance")
	adapter.record_reach(1000)
	report.check(adapter.snapshot().first_summit_run_number == summit_run, "later summit cannot replace first summit run")
	adapter.fund_preview()
	var success_count: int = 0
	for node: Dictionary in nodes:
		if adapter.purchase(node): success_count += 1
	report.check(success_count == 30 and adapter.snapshot().pending_points == 0, "only 30 existing ranks purchasable even at full preview funding")
	before = adapter.snapshot()
	adapter.reset_purchased()
	var reset: Dictionary = adapter.snapshot()
	report.check(reset.ranks == {"strength":0,"endurance":0,"recovery":0}, "preview reset clears purchased ranks")
	report.check(reset.first_reach_flags == before.first_reach_flags and reset.first_summit_run_number == before.first_summit_run_number and count_eligible(reset) == 35, "preview reset preserves permanent eligibility")
	report.check(reset.total_xp == before.total_xp and reset.current_run_number == before.current_run_number, "preview reset is not a fabricated prestige economy")
	adapter.apply_fixture("250")
	adapter.purchase_succeeded.connect(func(_id: String): recursive_purchase_result = adapter.purchase(second))
	report.check(adapter.purchase(first), "first purchase succeeds with reentrant callback")
	report.check(not recursive_purchase_result and adapter.snapshot().ranks.strength == 1, "reentrant purchase callback cannot double-spend")
	quit(report.finish("state_tests", {"fixtures":fixture_results,"scope":"in-memory mock adapter, unchanged Progression, resolver states and permanent-eligibility semantics; no game integration"}))
