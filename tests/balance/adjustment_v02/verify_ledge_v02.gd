extends SceneTree

const Factory = preload("res://tests/balance/adjustment_v02/controller_factory.gd")
const Terrain = preload("res://tests/balance/adjustment_v02/terrain.gd")
const DT: float = 1.0 / 120.0
var factory = Factory.new()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not factory.build():
		quit(1)
		return
	var candidates: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/balance/adjustment_v02/d-selection.json")).candidates
	candidates.BASE = {}
	candidates.G123 = {"uphill_recovery_after_m":750.0,"uphill_recovery_scale":0.0,"geometry_overrides":[{"chunk_index":15,"angle":45.0,"surface":"STONE","climb_length":50.0,"wet_ranges":[]},{"chunk_index":16,"angle":45.0,"surface":"STONE","climb_length":50.0,"wet_ranges":[]},{"chunk_index":17,"angle":45.0,"surface":"STONE","climb_length":23.0,"wet_ranges":[]}]}
	var trials: Array = []
	var failures: int = 0
	for name: String in candidates:
		var config: Dictionary = candidates[name]
		var world = Terrain.new(101,false,6,"")
		world.configure_experiment(config)
		var target: Dictionary = {}
		for ledge: Dictionary in world.ledges:
			if float(ledge.distance) >= 500.0:
				target = ledge
				if world.ledge_relocations.any(func(item): return item.id == ledge.id):
					break
		if target.is_empty() or not is_equal_approx(float(target.required_push),1.6):
			failures += 1
			continue
		for method: String in ["slow_normal","sweet_normal","fast_normal","slow_shift","sweet_shift","fast_shift","low_stamina_shift","post_slip_shift","release_to_full_then_shift","blocked_release_reapproach"]:
			var stone: BoulderController = factory.create(world,config)
			stone.distance = float(target.distance)-0.001
			stone.peak = stone.distance
			stone.velocity = 0.8 if method.begins_with("sweet") else (1.6 if method.begins_with("fast") else 0.2)
			if method == "blocked_release_reapproach":
				stone.velocity = 1.6
			if method in ["low_stamina_shift","release_to_full_then_shift"]:
				stone.stamina = 5.0
			if method == "release_to_full_then_shift":
				stone.distance = float(target.distance)-0.1
				stone.peak = stone.distance
				stone.velocity = 0.0
			if method == "post_slip_shift":
				stone.slip_remaining = 0.7
				stone.velocity = -0.65
			var initial: Dictionary = stone.snapshot()
			var phase: String = "recover" if method == "release_to_full_then_shift" else "push"
			var events: Array = []
			var block_count: int = 0
			var minimum_distance: float = stone.distance
			var full_recovery_seen: bool = false
			for step: int in range(120*35):
				if phase == "recover" and stone.stamina >= stone.max_stamina-0.000001:
					full_recovery_seen = true
					phase = "push"
					events.append({"event":"full_recovery","state":stone.snapshot()})
				if phase == "retreat" and stone.velocity >= 0.0:
					phase = "push"
					events.append({"event":"reapproach","state":stone.snapshot()})
				var push: bool = phase == "push"
				var exert: bool = push and not method.ends_with("normal")
				stone._step_v02(DT,push,exert,false)
				minimum_distance = minf(minimum_distance,stone.distance)
				if stone.ledge_blocked:
					block_count += 1
					if events.size() < 12:
						events.append({"event":"blocked","state":stone.snapshot(),"push_force":stone.push_force})
					if method == "blocked_release_reapproach":
						phase = "retreat"
				if stone.cleared_ledges.has(str(target.id)) or stone.state != "climbing":
					break
			trials.append({"candidate_id":name,"candidate":config,"seed":101,"weather":world.weather_id,"method":method,"initial_state_fixture":true,"state_mutations_after_initialization":false,"target":target,"target_on_shelf":world.is_shelf(float(target.distance)),"target_relocated":world.ledge_relocations.any(func(item):return item.id == target.id),"initial_state":initial,"final_state":stone.snapshot(),"cleared":stone.cleared_ledges.has(str(target.id)),"blocked_steps":block_count,"retreat_m":float(initial.distance)-minimum_distance,"full_recovery_seen":full_recovery_seen,"events":events})
	var output := FileAccess.open("res://tests/balance/results/act1-adjustment-v02/ledge-v02-diagnostics.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"source_sha256":Factory.SOURCE_SHA256,"trials":trials,"structural_failures":failures,"limitations":"Seed101 natural weather; zero ranks; bounded local fixtures, not population or full-route proof. All approaches initially fixture state. Recovery/retreat after fixture uses legal inputs only. Failure to clear in35s is not impossibility. No ledge force threshold modified."},"\t"))
	output.close()
	print("LEDGE V02: ",trials.size()," trials; ",failures," structural failures")
	quit(1 if failures else 0)
