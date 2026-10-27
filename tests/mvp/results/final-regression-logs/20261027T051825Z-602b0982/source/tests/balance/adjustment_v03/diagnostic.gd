extends "res://tests/balance/adjustment_v03/simulator.gd"

# Same CLI/jobs as the observed harness. Direct source-derived fixed steps
# omit observer-only bands/stall traces. Entry fixtures never earn XP.
func supports_entry_fixture() -> bool:
	return true

func valid_job(job: Dictionary) -> bool:
	if job.has("stop_after_m") and str(job.get("mode","single"))!="single": return false
	if job.has("entry_fixture"):
		if str(job.get("mode","single"))!="single" or not bool(job.get("diagnostic_fixture",false)): return false
		var fixture: Dictionary=job.entry_fixture
		if float(fixture.get("stamina_fraction",1.0))<0.0 or float(fixture.get("stamina_fraction",1.0))>1.0: return false
		if float(fixture.get("distance_m",0.0))<0.0 or float(fixture.get("distance_m",0.0))>=1000.0: return false
	return super.valid_job(job)

func simulate_run(job: Dictionary,seed_value: int,profile: Dictionary,run_index: int,campaign_id: String) -> Dictionary:
	active_job=job
	var world:=create_world(seed_value,job)
	var candidate: Dictionary=job.get("candidate",{})
	configure_world(world,candidate)
	var stone: BoulderController=create_controller(world,candidate)
	apply_growth(stone,profile.ranks,candidate)
	stone.stamina=stone.max_stamina
	var growth: Progression=profile.progression
	var starting_progression: Dictionary=growth.snapshot()
	var starting_ranks: Dictionary=profile.ranks.duplicate()
	growth.begin_run()
	if job.has("entry_fixture"):
		stone.distance=float(job.entry_fixture.get("distance_m",0.0))
		stone.peak=stone.distance
		stone.velocity=float(job.entry_fixture.get("velocity",0.0))
		stone.stamina=stone.max_stamina*float(job.entry_fixture.get("stamina_fraction",1.0))
	var start_state: Dictionary=stone.snapshot()
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed_value ^ 0x4150494C
	var policy: Dictionary=policies[str(job.policy)]
	var cadence: int=maxi(1,int(round(float(policy.decision_seconds)/DT)))
	var command: Array=[false,false,false]
	var memory: Dictionary={"resting":false}
	var earned: int=0
	var xp_events: Array=[]
	var runaways: int=0
	var decisions: int=0
	var raw:=PackedByteArray()
	for step: int in range(int(floor(float(job.get("max_run_seconds",1800))/DT))):
		if stone.state in ["result","summit"]: break
		if not job.has("entry_fixture"): purchase(job,profile,stone)
		if step%cadence==0:
			command=decide(stone,policy,memory,rng,str(job.policy))
			decisions+=1
		raw.append(int(command[0])+2*int(command[1])+4*int(command[2]))
		var before_state: String=stone.state
		stone._step_v02(DT,command[0],command[1],command[2])
		if before_state!="runaway" and stone.state=="runaway": runaways+=1
		if not job.has("entry_fixture") and int(stone.peak/50.0)>growth.run_milestones:
			var gained: int=award(profile,stone)
			earned+=gained
			xp_events.append({"seconds":float(profile.time)+stone.elapsed,"run_seconds":stone.elapsed,"peak_m":stone.peak,"earned_xp":gained,"total_xp":growth.total_xp,"level":growth.level(),"pending_points":growth.pending_points()})
		if job.has("stop_after_m") and stone.distance>=float(job.stop_after_m): break
	var status: String="summit" if stone.state=="summit" else ("fall" if stone.state=="result" else ("diagnostic_target" if job.has("stop_after_m") and stone.distance>=float(job.stop_after_m) else "timeout"))
	var row: Dictionary=identifiers(job,seed_value,campaign_id)
	row.merge({"type":"run","physics_mode":"direct audited production _step_v02 120Hz; observer omitted","diagnostic_fixture":job.has("entry_fixture"),"entry_fixture":job.get("entry_fixture"),"run_index":run_index,"status":status,"completed":status=="summit","censored":status=="timeout","seconds":stone.elapsed,"peak_m":stone.peak,"final_distance_m":stone.distance,"slips":stone.slips,"runaways":runaways,"earned_xp":earned,"cumulative_xp":profile.earned,"total_xp":growth.total_xp,"xp_events":xp_events,"start_ranks":starting_ranks,"end_ranks":profile.ranks.duplicate(),"progression_start":starting_progression,"progression_end":growth.snapshot(),"initial_state":start_state,"final_state":stone.snapshot(),"weather":world.weather_id,"gate_telemetry":stone.gate_ledger.values().duplicate(true),"geometry_layout":world.experiment_layout(),"decision_count":decisions,"decision_cadence_seconds":cadence*DT,"run_start_seconds":profile.time,"steps":raw.size()})
	var context:=HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(raw)
	row.input_sha256=context.finish().hex_encode()
	var path: String=output.get_path().get_base_dir().path_join("input-traces")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	path=path.path_join("%s-seed%d-run%d-%s.bin.gz"%[job.id,seed_value,run_index,FileAccess.get_sha256("res://tests/balance/adjustment_v03/diagnostic.gd").substr(0,12)])
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(raw.compress(FileAccess.COMPRESSION_GZIP))
	row.input_trace_gzip=path
	profile.time=float(profile.time)+stone.elapsed
	emitted_runs+=1
	return row
