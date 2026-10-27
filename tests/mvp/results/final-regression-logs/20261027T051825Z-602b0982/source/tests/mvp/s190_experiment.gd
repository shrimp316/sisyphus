extends "res://tests/balance/adjustment_v03/simulator.gd"

const TestTerrain = preload("res://tests/mvp/s190_terrain.gd")
const TestBoulder = preload("res://tests/mvp/s190_boulder.gd")
const MasteryProfile = preload("res://scripts/mastery_progression.gd")
const BUILDS: Dictionary = {"zero":[0,0,0],"balanced18":[6,6,6],"strength18":[10,4,4],"endurance18":[4,10,4],"breath18":[4,4,10],"all30":[10,10,10]}
const POLICY_NAMES: Array[String] = ["regular_recovery","skilled_recovery"]
const CANDIDATE: Dictionary = {"id":"S190_MVP","gates":[{"id":"late_gate","start_m":750.0,"end_m":940.0,"angle_degrees":45.0,"surface":"STONE","dry":true,"drain_scale":1.0,"slip_gain_scale":0.6,"slip_decay_scale":1.0,"recovery_seconds_budget":80.0/7.0,"recovery_rate":7.0,"recovery_min_stamina":1.0}],"connection_layout":[{"start_m":940.0,"end_m":950.0,"shelf":true,"surface":"STONE","dry":true,"angle_degrees":0.0}]}
var result_directory: String = "res://tests/mvp/results/s190"

func _initialize() -> void:
	# Reuse only inherited decision methods; never build the old SHA-pinned factory.
	call_deferred("run")

func funded_profile(counts: Array):
	var profile = MasteryProfile.new()
	var cost: int = 0
	for count: int in counts:
		for i: int in range(count): cost += int(profile.balance.normal_costs[i])
	var farming_runs: int = 0
	while profile.available_exp < cost:
		profile.begin_run("fixture-funding-%d"%farming_runs)
		profile.award_distance(750.0,1000.0)
		farming_runs += 1
	for kind: int in range(3):
		for i: int in range(int(counts[kind])):
			assert(profile.purchase_node("%s%02d"%[["STR","END","BRE"][kind],i+1]),"Actual fixture purchase failed")
	profile.begin_run("experiment-run")
	return {"profile":profile,"cost":cost,"funding_award_calls":farming_runs}

func run_case(seed_value: int, build: String, policy_name: String, entry_fixture: bool) -> Dictionary:
	var world = TestTerrain.new(seed_value,false,6,"clear")
	world.configure_experiment(CANDIDATE)
	var funded: Dictionary = funded_profile(BUILDS[build])
	var profile = funded.profile
	var stone = TestBoulder.new(world)
	stone.apply_mastery_effects(profile.get_mastery_modifiers())
	stone.stamina=stone.max_stamina
	if entry_fixture:
		stone.distance=750.0
		stone.peak=750.0
		stone.velocity=1.8
	var initial: Dictionary=stone.snapshot()
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed_value ^ 0x4150494C
	var policy: Dictionary=policies[policy_name]
	var cadence: int=maxi(1,int(round(float(policy.decision_seconds)/DT)))
	var memory: Dictionary={"resting":false}
	var command: Array=[false,false,false]
	var raw:=PackedByteArray()
	var exhaustion: int=0
	var runaways: int=0
	for step: int in range(216000):
		if stone.state in ["result","summit"] or (entry_fixture and stone.distance>=940.0): break
		if step%cadence==0: command=decide(stone,policy,memory,rng,policy_name)
		raw.append(int(command[0])+2*int(command[1])+4*int(command[2]))
		var before_stamina: float=stone.stamina
		var before_state: String=stone.state
		stone.advance(DT,command[0],command[1],command[2])
		if before_stamina>0.0 and stone.stamina<=0.0: exhaustion+=1
		if before_state!="runaway" and stone.state=="runaway": runaways+=1
	var status: String="gate_exit" if entry_fixture and stone.distance>=940.0 else ("summit" if stone.state=="summit" else ("fall" if stone.state=="result" else "timeout"))
	var id: String="%s-%s-%s-%d"%["fixture" if entry_fixture else "route",build,policy_name,seed_value]
	var trace: String=result_directory.path_join(id+".bin.gz")
	var file:=FileAccess.open(trace,FileAccess.WRITE)
	file.store_buffer(raw.compress(FileAccess.COMPRESSION_GZIP))
	file.close()
	var digest:=HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(raw)
	return {"id":id,"seed":seed_value,"weather":"clear","generation":6,"build":build,"counts":BUILDS[build],"policy":policy_name,"entry_fixture":entry_fixture,"initial_state":initial,"final_state":stone.snapshot(),"seconds":stone.elapsed,"peak_m":stone.peak,"status":status,"completed":status in ["gate_exit","summit"],"censored":status=="timeout","slips":stone.slips,"exhaustion_episodes_after_rescue":exhaustion,"runaways":runaways,"gate":stone.experiment_snapshot(),"mastery_profile":profile.snapshot(),"modifiers":profile.get_mastery_modifiers(),"purchase_cost":funded.cost,"funding_award_calls":funded.funding_award_calls,"steps":raw.size(),"input_sha256":digest.finish().hex_encode(),"input_trace":trace,"decision_cadence_seconds":cadence*DT}

func run() -> void:
	policies=JSON.parse_string(FileAccess.get_file_as_string(policy_path())).policies
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(result_directory))
	var file:=FileAccess.open(result_directory.path_join("results.jsonl"),FileAccess.WRITE)
	var hashes: Dictionary={}
	for path: String in ["scripts/boulder_controller.gd","scripts/mastery_boulder.gd","scripts/mastery_effects.gd","scripts/mastery_progression.gd","data/mastery/nodes.json","data/mastery/balance.json","data/mastery/feature_flags.json","tests/mvp/s190_experiment.gd","tests/mvp/s190_boulder.gd","tests/mvp/s190_terrain.gd","tests/balance/adjustment_v03/simulator.gd","tests/balance/adjustment_v03/policies.json"]:
		hashes[path]=FileAccess.get_sha256("res://"+path)
	file.store_line(JSON.stringify({"type":"metadata","source_sha256":hashes,"candidate":CANDIDATE,"builds":BUILDS,"policies":policies,"scope":"Fixed purchased builds, not natural XP campaigns. Actual wallet award/purchase APIs create fixtures; funding distance awards are artificial setup, not simulated completed climbs. Two synthetic recovery-aware policies; not human participants. No grown-build reuse of old impossibility proof. Environmental quota does not cap added BRE recovery/rescue."}))
	file.flush()
	var total: int=0
	for entry_fixture: bool in [true,false]:
		for build: String in BUILDS:
			for policy_name: String in POLICY_NAMES:
				for seed_value: int in [101,202,303]:
					var row: Dictionary=run_case(seed_value,build,policy_name,entry_fixture)
					row.type="run"
					file.store_line(JSON.stringify(row))
					file.flush()
					total+=1
					print(total," ",row.id," ",row.status," peak=",row.peak_m)
	file.close()
	quit(0)
