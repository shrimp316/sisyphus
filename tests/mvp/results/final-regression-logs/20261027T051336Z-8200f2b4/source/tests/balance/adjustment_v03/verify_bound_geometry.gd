extends "res://tests/balance/adjustment_v03/verify_recovery_bound.gd"

const V3Terrain = preload("res://tests/balance/adjustment_v03/terrain.gd")

func run() -> void:
	var count: int = 0
	var sampled_points: int = 0
	var failures: Array = []
	var angle_candidates: bool = "--angle-candidates" in OS.get_cmdline_user_args()
	var expansion_seeds: bool = "--expansion-seeds" in OS.get_cmdline_user_args()
	var seed_start: int = 3001 if expansion_seeds else 1001
	var full_candidates: bool = "--full-candidates" in OS.get_cmdline_user_args() or angle_candidates
	var configs: Array = []
	for length: float in [190.0,255.0]:
		var budget: float = 80.0 if length==190.0 else 140.0
		var config: Dictionary = candidate(budget,1.0,length)
		var gate: Dictionary = config.gates[0]
		config.connection_layout=[{"start_m":gate.end_m,"end_m":float(gate.end_m)+10.0,"shelf":true,"surface":"STONE"}]
		configs.append(config)
	var source_config: String = "res://tests/balance/adjustment_v03/"+("candidates_angle_followup.json" if angle_candidates else "candidates_full_pilot.json")
	var source_hash: String = FileAccess.get_sha256(source_config) if full_candidates else ""
	if full_candidates: configs=JSON.parse_string(FileAccess.get_file_as_string(source_config))
	var only_s190: bool = "--only-s190" in OS.get_cmdline_user_args()
	if only_s190: configs=configs.filter(func(config):return config.get("id","")=="S190")
	var certificates: Array = []
	for config: Dictionary in configs:
		var gate: Dictionary = config.gates.back()
		var length: float = float(gate.end_m)-float(gate.start_m)
		var angle: float = float(gate.angle_degrees)
		var budget: float = float(gate.recovery_seconds_budget)*float(gate.recovery_rate)
		var bound: Dictionary = certificate(0,0,0,budget,length,angle)
		bound.candidate_id=config.get("id",str(length))
		bound.gate=gate
		certificates.append(bound)
		var scalar_ok: bool = angle>=39.0 and angle<=45.0 and str(gate.surface)=="STONE" and float(gate.get("drain_scale",1.0))==1.0 and float(gate.recovery_min_stamina)>0.0 and float(config.get("push_scale",1.0))==1.0 and float(config.get("drain_scale",1.0))==1.0 and float(config.get("late_grip_scale",1.0))==1.0
		for seed_value: int in range(seed_start,seed_start+100):
			for weather: String in ["clear","rain"]:
				var world=V3Terrain.new(seed_value,false,6,weather)
				world.configure_experiment(config)
				var baseline=MountainManager.new(seed_value,false,6,weather)
				var ok: bool = scalar_ok and is_equal_approx(world.total_length,1000.0)
				for meter: int in range(250):
					ok = ok and world.segment_at(meter+.5)==baseline.segment_at(meter+.5)
				for offset: int in range(int(length)):
					var position: float = float(gate.start_m)+offset+.001
					sampled_points+=1
					ok = ok and not world.is_shelf(position) and not world.wet_at(position) and str(world.surface_at(position).id)=="STONE" and is_equal_approx(world.angle_at(position),deg_to_rad(angle)) and is_equal_approx(world.grip_at(position),1.0) and is_equal_approx(world.resistance_at(position),0.2)
				ok = ok and world.is_shelf(float(gate.start_m)-.001) and world.is_shelf(float(gate.end_m)+.001)
				for ledge: Dictionary in world.ledges:
					ok = ok and not (float(ledge.distance)>=float(gate.start_m) and float(ledge.distance)<float(gate.end_m))
					ok = ok and is_equal_approx(float(ledge.required_push),1.6)
				for point: float in world.rest_points:
					ok = ok and not (point>=float(gate.start_m) and point<float(gate.end_m))
				count+=1
				if not ok: failures.append({"candidate_id":config.get("id",str(length)),"length":length,"seed":seed_value,"weather":weather})
	var source_unchanged: bool = not full_candidates or source_hash==FileAccess.get_sha256(source_config)
	if not source_unchanged: failures.append({"error":"source configuration changed during verification"})
	var output_name: String="S190-expansion-seed-certificate.json" if only_s190 and expansion_seeds else ("angle-candidate-expansion-seed-certificates.json" if angle_candidates and expansion_seeds else ("angle-candidate-certificates.json" if angle_candidates else ("full-candidate-expansion-seed-certificates.json" if full_candidates and expansion_seeds else ("full-candidate-certificates.json" if full_candidates else "bound-geometry-verification.json"))))
	var output:=FileAccess.open("res://tests/balance/results/act1-adjustment-v03/"+output_name,FileAccess.WRITE)
	output.store_string(JSON.stringify({"cases":count,"seed_start":seed_start,"seed_end":seed_start+99,"weather_conditions":["clear","rain"],"gate_sample_points":sampled_points,"failures":failures,"certificates":certificates,"source_config":source_config if full_candidates else null,"source_config_sha256":source_hash,"source_config_unchanged":source_unchanged,"terrain_sha256":FileAccess.get_sha256("res://tests/balance/adjustment_v03/terrain.gd"),"scope":"Last gate certificate for each exact candidate;100 seeds x2weather each; early250 unchanged; last gate dry constant39..45degrees STONE/grip1/resistance.2; no internal ledge/support/shelf; safe before/after; unchanged ledge requirement. Earlier gates' passability and full route are not established here. Structural finite samples support source inspection, not all seeds enumeration."},"\t"))
	output.close()
	print("V03 GEOMETRY ",count," cases, ",sampled_points," points, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)
