extends SceneTree

# Independent upper bound and constructive witnesses. The bound is policy-free;
# witnesses are deliberately ideal 120 Hz feedback, not human simulations.
const Factory = preload("res://tests/balance/adjustment_v02/controller_factory.gd")
const Terrain = preload("res://tests/balance/adjustment_v02/terrain.gd")
const DT: float = 1.0 / 120.0
var factory = Factory.new()

func _initialize() -> void:
	call_deferred("run")

func certificate(angle: float, length: float, strength: int, endurance: int) -> Dictionary:
	var p: float = 1.0 + 0.02 * strength
	var capacity: float = 100.0 * (1.0 + 0.02 * endurance)
	var drain: float = BoulderController.new().slope_drain_multiplier(angle)
	var bounds: Array = []
	# Upper endpoints cover every pre-step velocity band, including rollback.
	for exert: bool in [false, true]:
		for band: Dictionary in [{"v": 0.45, "momentum": 1.0, "control": 1.0, "drain": 1.0}, {"v": 1.2, "momentum": 1.1, "control": 1.0, "drain": 0.8}, {"v": 1.5, "momentum": 1.0, "control": 1.0, "drain": 1.0}, {"v": 1.8, "momentum": 1.0, "control": 0.9, "drain": 1.0}]:
			var force: float = 2.6 * p * float(band.momentum) * float(band.control) * (1.65 if exert else 1.0)
			var speed: float = minf(1.8, float(band.v) + force * DT)
			bounds.append(force * speed / (drain * float(band.drain) * (3.0 if exert else 1.0)))
	var work_per_weighted_stamina: float = bounds.max()
	var weighted_stamina: float = 0.885 * capacity + 3.0 * drain * DT
	var gravity_minus_resistance: float = 3.0 * sin(deg_to_rad(angle)) - 0.2
	var initial_energy: float = 0.5 * 1.8 * 1.8
	var upper_budget: float = work_per_weighted_stamina * weighted_stamina + initial_energy
	var required: float = gravity_minus_resistance * (length - 1.8 * DT)
	return {"angle_degrees": angle, "length_m": length, "ranks": {"strength": strength, "endurance": endurance}, "min_retarding_acceleration": gravity_minus_resistance, "drain_multiplier": drain, "work_per_weighted_stamina_upper": work_per_weighted_stamina, "weighted_stamina_upper": weighted_stamina, "entry_kinetic_energy_upper": initial_energy, "optimistic_budget_upper": upper_budget, "necessary_work_lower": required, "impossible_if_negative_margin": upper_budget - required, "zero_input_space_certificate": upper_budget < required, "assumptions": "Constant dry STONE gate; no stamina recovery inside; no positive external impulses; no purchase inside; initial stamina <= capacity, speed <=1.8. Discrete semi-implicit integration; all ordinary input combinations, arbitrary timing and retreat included. Bound cannot certify feasibility when its margin is positive."}

func probe(strength: int, endurance: int, recovery: int, target: float, angle: float, length: float) -> Dictionary:
	var world = Terrain.new(101, false, 6, "clear")
	var overrides: Array = []
	for index: int in range(15, 18):
		overrides.append({"chunk_index": index, "angle": angle, "surface": "STONE", "climb_length": 50.0 if index < 17 else length - 100.0, "wet_ranges": []})
	var config: Dictionary = {"geometry_overrides": overrides, "uphill_recovery_after_m": 750.0, "uphill_recovery_scale": 0.0}
	world.configure_experiment(config)
	var sim: BoulderController = factory.create(world, config)
	sim.apply_progression({"strength": strength, "endurance": endurance, "recovery": recovery})
	sim.stamina = sim.max_stamina
	sim.distance = 750.0
	sim.peak = 750.0
	sim.velocity = 1.8
	var start: Dictionary = sim.snapshot()
	var steps: int = 0
	for step: int in range(120 * 400):
		var push: bool = sim.velocity < target
		var sweet: float = 1.1 if sim.velocity >= 0.45 and sim.velocity <= 1.2 else 1.0
		var force: float = 2.6 * sim.push_multiplier * sim.stamina_multiplier() * sweet
		var opposition: float = 3.0 * sin(deg_to_rad(angle)) + 0.2
		var exert: bool = force < opposition + 0.005 or sim.velocity < 0.15
		sim.advance(DT, push, exert and push, false)
		steps += 1
		if sim.distance >= 750.0 + length or sim.state != "climbing" or sim.distance < 750.0:
			break
	return {"ranks": {"strength": strength, "endurance": endurance, "recovery": recovery}, "target_speed": target, "crossed": sim.distance >= 750.0 + length, "distance_gain_m": sim.peak - 750.0, "seconds": steps * DT, "state": sim.state, "initial_state": start, "final_state": sim.snapshot(), "policy": "ideal120Hz normal/coast speed target; exert when normal force cannot overcome grade or starting; no state mutation after initial fixture", "is_entry_fixture": true}

func run() -> void:
	if not factory.build():
		quit(1)
		return
	var bounds: Array = []
	var witnesses: Array = []
	var growth_search: bool = "--growth-search" in OS.get_cmdline_user_args()
	var rank_sets: Array = [[0,0,0], [3,3,3], [5,5,5], [8,8,8], [9,9,9], [10,10,10]] if growth_search else [[0,0,0], [8,8,8], [9,9,9], [10,8,0], [8,10,0], [10,10,10]]
	var targets: Array = [0.8, 1.0, 1.15, 1.195, 1.3] if growth_search else [1.15, 1.195]
	for ranks: Array in rank_sets:
		bounds.append(certificate(45.0, 123.0, ranks[0], ranks[1]))
		for target: float in targets:
			witnesses.append(probe(ranks[0], ranks[1], ranks[2], target, 45.0, 123.0))
	var payload: Dictionary = {"source_sha256": Factory.SOURCE_SHA256, "method": "Independent discrete potential bound plus deliberately ideal fixed-state gate entry witnesses. Not a population completion rate.", "certificates": bounds, "witnesses": witnesses}
	payload.failed_witness_interpretation = "Bounded policy search failure alone is not impossibility. Positive certificate margins do not establish feasibility."
	var output := FileAccess.open("res://tests/balance/results/act1-adjustment-v02/" + ("gate-growth-search.json" if growth_search else "gate-bound-123.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(payload, "\t"))
	output.close()
	for bound: Dictionary in bounds:
		print("BOUND ", JSON.stringify(bound))
	for witness: Dictionary in witnesses:
		print("WITNESS ", witness.ranks, " target=", witness.target_speed, " crossed=", witness.crossed, " peak_gain=", witness.distance_gain_m)
	quit(0)
