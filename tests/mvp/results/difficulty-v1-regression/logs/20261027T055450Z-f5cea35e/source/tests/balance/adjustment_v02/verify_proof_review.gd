extends SceneTree

# Independent review fixtures, not a new physical model or experiment result.
const Factory = preload("res://tests/balance/adjustment_v02/controller_factory.gd")
const Terrain = preload("res://tests/balance/adjustment_v02/terrain.gd")
const DT: float = 1.0 / 120.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var factory = Factory.new()
	if not factory.build():
		quit(2)
		return
	var config: Dictionary = {"uphill_recovery_after_m": 750.0, "uphill_recovery_scale": 0.0, "geometry_overrides": [{"chunk_index": 15, "angle": 45.0, "surface": "STONE", "climb_length": 50.0, "wet_ranges": []}, {"chunk_index": 16, "angle": 45.0, "surface": "STONE", "climb_length": 50.0, "wet_ranges": []}, {"chunk_index": 17, "angle": 45.0, "surface": "STONE", "climb_length": 23.0, "wet_ranges": []}]}
	var world = Terrain.new(101, false, 6, "clear")
	world.configure_experiment(config)
	var c: float = 3.0 * sin(PI / 4.0) - 0.2
	var max_work: float = 2.5736495098039214
	var count: int = 0
	var failures: int = 0
	var max_violation: float = -INF
	var worst: Dictionary = {}
	for v: float in [-3.999, -3.5, -2.0, -0.1, -0.01, -0.001, 0.0, 0.001, 0.01, 0.15, 0.150001, 0.449999, 0.45, 1.2, 1.200001, 1.5, 1.500001, 1.8]:
		for s: float in [0.0, 0.000001, 0.02, 19.999999, 20.0, 20.000001, 49.999999, 50.0, 50.000001, 100.0]:
			for slip_value: float in [0.0, 99.999999]:
				for remaining: float in [0.0, 0.7]:
					for command: int in range(8):
						var sim: BoulderController = factory.create(world, config)
						sim.distance = 800.0
						sim.peak = 800.0
						sim.velocity = v
						sim.stamina = s
						sim.slip = slip_value
						sim.slip_remaining = remaining
						var multiplier: float = sim.stamina_multiplier()
						var push: bool = bool(command & 1)
						var exert: bool = bool(command & 2)
						var brace: bool = bool(command & 4)
						var h_before: float = c * sim.distance + 0.5 * maxf(v, 0.0) * maxf(v, 0.0)
						sim.advance(DT, push, exert, brace)
						var h_after: float = c * sim.distance + 0.5 * maxf(sim.velocity, 0.0) * maxf(sim.velocity, 0.0)
						var charge: float = 0.0
						if sim.action in ["push", "exert"]:
							charge = multiplier * 1.7 * DT * (3.0 if exert and push else 1.0) * (0.8 if v >= 0.45 and v <= 1.2 else 1.0)
						var violation: float = h_after - h_before - max_work * charge
						count += 1
						if violation > max_violation:
							max_violation = violation
							worst = {"velocity": v, "stamina": s, "slip": slip_value, "slip_remaining": remaining, "command": [push, exert, brace], "potential_delta": h_after - h_before, "work_bound": max_work * charge, "final": sim.snapshot()}
						if violation > 0.00000001:
							failures += 1
	var payload: Dictionary = {"kind": "independent_boundary_fixture_audit_not_gameplay_sampling", "checks": count, "failures": failures, "max_violation": max_violation, "worst": worst, "tolerance": 0.00000001, "limitation": "Finite boundary-state grid corroborates algebra; not exhaustive proof over continuous states", "source_sha256": Factory.SOURCE_SHA256}
	var output_path: String = "res://tests/balance/results/act1-adjustment-v02/proof-review-step.json"
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(arguments.size() - 1):
		if arguments[index] == "--output":
			output_path = arguments[index + 1]
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	print("PROOF REVIEW: ", count, " boundary fixtures, failures=", failures, " max violation=", max_violation)
	quit(1 if failures else 0)
