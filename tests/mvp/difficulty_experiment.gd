extends "res://tests/balance/simulator.gd"
## Inherit only the archived synthetic decision rule; execute actual MVP controllers.
const LegacyMastery = preload("res://scripts/mastery_boulder.gd")
const DifficultyClimb = preload("res://scripts/mvp/climb_boulder.gd")
const Wallet = preload("res://scripts/mastery_progression.gd")
const FIXED_BUILDS: Dictionary = {"zero":[0,0,0],"balanced18":[6,6,6],"all30":[10,10,10]}
var trace_directory: String
var difficulty_defaults: Dictionary

func _initialize() -> void:
	call_deferred("run")

func fixture(build: String) -> Dictionary:
	var profile = Wallet.new()
	var counts: Array = FIXED_BUILDS[build]
	var cost: int = 0
	for rank: int in counts:
		for index: int in range(rank): cost += int(profile.balance.normal_costs[index])
	var awards: int = 0
	while profile.available_exp < cost:
		profile.begin_run("artificial-fixture-%d" % awards)
		profile.award_distance(750,1000)
		awards += 1
	for category: int in range(3):
		for rank: int in range(counts[category]):
			assert(profile.purchase_node("%s%02d" % [["STR","END","BRE"][category],rank+1]))
	profile.begin_run("fixed-experiment")
	return {"profile":profile,"cost":cost,"artificial_award_calls":awards}

func simulate_case(job: Dictionary, seed_value: int) -> Dictionary:
	var world := MountainManager.new(seed_value,false,6,str(job.get("weather","clear")))
	var funded: Dictionary = fixture(job.build)
	var profile = funded.profile
	var stone = LegacyMastery.new(world) if job.candidate == "legacy" else DifficultyClimb.new(world)
	var settings: Dictionary = {}
	if job.candidate != "legacy":
		settings = difficulty_defaults.duplicate(true)
		settings.merge(job.get("overrides",{}),true)
		stone.configure_difficulty(settings)
	stone.apply_mastery_effects(profile.get_mastery_modifiers())
	stone.stamina = stone.max_stamina
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x4150494C
	var policy: Dictionary = policies.get(job.policy,{"decision_seconds":DT})
	var cadence: int = maxi(1,int(round(float(policy.decision_seconds)/DT)))
	var command: Array = [true,false,false]
	var memory: Dictionary = {"resting":false}
	var raw := PackedByteArray()
	var exhaustion: int = 0
	var normal_slips: int = 0
	var normal_seconds: float = 0.0
	var released_seconds: float = 0.0
	var shelter_rest_seconds: float = 0.0
	var exhausted_seconds: float = 0.0
	var first_250: Variant = null
	var surfaces: Dictionary = {}
	var max_steps: int = int(float(job.get("max_seconds",1800))*120.0)
	var inputs_at_slip: Array[Dictionary] = []
	for step: int in range(max_steps):
		if stone.state in ["result","summit"]: break
		if job.policy != "hold_D" and step % cadence == 0:
			command = decide(stone,policy,memory,rng,job.policy)
		raw.append(int(command[0])+2*int(command[1])+4*int(command[2]))
		var before: Dictionary = {"stamina":stone.stamina,"slips":stone.slips,"distance":stone.distance,"velocity":stone.velocity,"state":stone.state}
		var surface: String = str(world.surface_at(stone.distance).id)
		var slope: float = rad_to_deg(world.angle_at(stone.distance))
		var angle_bin: String = "0-15" if slope<=15 else ("15-25" if slope<=25 else ("25-35" if slope<=35 else "35-45"))
		var key: String = surface+"|"+angle_bin
		if not surfaces.has(key):
			surfaces[key] = {"surface":surface,"angle_bin":angle_bin,"exposure_seconds":0.0,"normal_push_seconds":0.0,
				"slips":0,"normal_slips":0,"exhaustions_after_rescue":0,"net_stamina_lost":0.0,"net_stamina_gained":0.0,"distance_forward":0.0}
		stone.advance(DT,command[0],command[1],command[2])
		if first_250 == null and stone.peak>=250.0: first_250=stone.elapsed
		if before.state != "climbing": continue
		var normal: bool = command[0] and not command[1] and not command[2]
		var released: bool = not command[0] and not command[2]
		var slipped: int = stone.slips-int(before.slips)
		var exhausted: bool = float(before.stamina)>0.0 and stone.stamina<=0.0
		if exhausted: exhaustion+=1
		if normal: normal_seconds+=DT
		if released: released_seconds+=DT
		if float(before.stamina)<=0.0: exhausted_seconds+=DT
		if released and absf(float(before.velocity))<=.05 and world.is_shelf(float(before.distance)): shelter_rest_seconds+=DT
		if slipped>0:
			if normal: normal_slips+=slipped
			inputs_at_slip.append({"seconds":stone.elapsed,"distance_m":before.distance,"surface":surface,"slope_degrees":slope,
				"input":command.duplicate(),"stamina_before":before.stamina,"stamina_after":stone.stamina})
		var bucket: Dictionary=surfaces[key]
		bucket.exposure_seconds+=DT
		if normal: bucket.normal_push_seconds+=DT
		bucket.slips+=slipped
		if normal: bucket.normal_slips+=slipped
		if exhausted: bucket.exhaustions_after_rescue+=1
		bucket.net_stamina_lost+=maxf(0.0,float(before.stamina)-stone.stamina)
		bucket.net_stamina_gained+=maxf(0.0,stone.stamina-float(before.stamina))
		bucket.distance_forward+=maxf(0.0,stone.distance-float(before.distance))
	var status: String="summit" if stone.state=="summit" else ("fall" if stone.state=="result" else "timeout")
	var id: String="%s-%d" % [job.id,seed_value]
	var trace: String=trace_directory.path_join(id+".bin.gz")
	var trace_file:=FileAccess.open(trace,FileAccess.WRITE)
	trace_file.store_buffer(raw.compress(FileAccess.COMPRESSION_GZIP))
	trace_file.close()
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(raw)
	return {"type":"run","id":id,"candidate":job.candidate,"config":settings,"seed":seed_value,"generation":6,"weather":str(job.get("weather","clear")),
		"policy":job.policy,"decision_cadence_seconds":cadence*DT,"build":job.build,"counts":FIXED_BUILDS[job.build],
		"fixed_fixture":true,"purchase_cost":funded.cost,"artificial_award_calls":funded.artificial_award_calls,"modifiers":profile.get_mastery_modifiers(),
		"status":status,"completed":status=="summit","censored":status=="timeout","seconds":stone.elapsed,"peak_m":stone.peak,
		"reached_250":first_250!=null,"first_250_seconds":first_250,"normal_slips":normal_slips,"slips":stone.slips,
		"exhaustions_after_rescue":exhaustion,"exhausted_seconds":exhausted_seconds,"normal_push_seconds":normal_seconds,
		"released_seconds":released_seconds,"shelter_stationary_released_seconds":shelter_rest_seconds,"terrain":surfaces.values(),
		"slip_events":inputs_at_slip,"final_state":stone.snapshot(),"steps":raw.size(),"input_sha256":hash.finish().hex_encode(),"input_trace":trace}

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var config_path: String=""
	var output_path: String=""
	for i: int in range(args.size()-1):
		if args[i]=="--config": config_path=args[i+1]
		if args[i]=="--output": output_path=args[i+1]
	if config_path.is_empty() or output_path.is_empty() or FileAccess.file_exists(output_path):
		printerr("Pass --config and a new --output; existing results are immutable.")
		quit(2)
		return
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config_path))
	difficulty_defaults=JSON.parse_string(FileAccess.get_file_as_string("res://data/mastery/difficulty.json"))
	policies=JSON.parse_string(FileAccess.get_file_as_string(policy_path())).policies
	trace_directory=output_path.get_base_dir().path_join("input-traces")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(trace_directory))
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	var hashes: Dictionary={}
	for path: String in ["scripts/boulder_controller.gd","scripts/mastery_boulder.gd","scripts/mastery_effects.gd","scripts/mastery_progression.gd","scripts/mvp/climb_boulder.gd","data/mastery/nodes.json","data/mastery/balance.json","data/mastery/feature_flags.json","data/mastery/difficulty.json","tests/balance/simulator.gd","tests/balance/policies.json","tests/mvp/difficulty_experiment.gd","scripts/mountain_manager.gd"]:
		hashes[path]=FileAccess.get_sha256("res://"+path)
	for resource: String in DirAccess.get_files_at("res://data/chunks"):
		if resource.ends_with(".tres"):
			hashes["data/chunks/"+resource]=FileAccess.get_sha256("res://data/chunks/"+resource)
	hashes[get_script().resource_path.trim_prefix("res://")]=FileAccess.get_sha256(get_script().resource_path)
	hashes[policy_path().trim_prefix("res://")]=FileAccess.get_sha256(policy_path())
	file.store_line(JSON.stringify({"type":"metadata","schema":"mvp-difficulty-v1","source_sha256":hashes,"config":config,"policies":policies,
		"godot":Engine.get_version_info().string,"dt":DT,"scope":"Fixed purchased mastery fixtures, not natural XP campaigns or human outcomes. Artificial funding calls are setup only. Original synthetic policies unchanged; optimized is not a proof of optimality. Policy failure is not physical impossibility. Terrain exposure excludes runaway; elapsed includes descent. Exhaustions observed after rescue and stamina loss/gain are net per step, not gross drain."}))
	file.flush()
	var count: int=0
	for job: Dictionary in config.jobs:
		for seed_value: int in job.seeds:
			var row: Dictionary=simulate_case(job,seed_value)
			file.store_line(JSON.stringify(row))
			file.flush()
			count+=1
			print(count," ",row.id," ",row.status," peak=",row.peak_m," normal_slip=",row.normal_slips)
	file.close()
	quit(0)
