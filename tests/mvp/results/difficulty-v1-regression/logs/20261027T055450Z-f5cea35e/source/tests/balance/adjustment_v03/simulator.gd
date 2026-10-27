extends "res://tests/balance/adjustment_v02/simulator.gd"

const V3Factory = preload("res://tests/balance/adjustment_v03/controller_factory.gd")
const V3Terrain = preload("res://tests/balance/adjustment_v03/terrain.gd")

func _initialize() -> void:
	factory=V3Factory.new()
	super._initialize()

func policy_path() -> String:
	return "res://tests/balance/adjustment_v03/policies.json"

func create_world(seed_value: int,job: Dictionary) -> MountainManager:
	return V3Terrain.new(seed_value,false,int(job.get("generation",6)),str(job.get("weather","")))

func valid_job(job: Dictionary) -> bool:
	if int(job.get("generation",6))!=6: return false
	if job.has("entry_fixture") and (not supports_entry_fixture() or not bool(job.get("diagnostic_fixture",false))):
		printerr("Entry fixtures are diagnostic only")
		return false
	var ordinary: Dictionary=job.duplicate(true)
	ordinary.candidate=ordinary.get("candidate",{}).duplicate(true)
	ordinary.candidate.erase("gates")
	ordinary.candidate.erase("connection_layout")
	if not super.valid_job(ordinary): return false
	var candidate: Dictionary=job.get("candidate",{})
	var intervals: Array=[]
	var ids: Dictionary={}
	for gate: Dictionary in candidate.get("gates",[]):
		var id: String=str(gate.get("id",""))
		if id.is_empty() or ids.has(id): return false
		ids[id]=true
		for key: String in ["drain_scale","slip_gain_scale","slip_decay_scale","recovery_seconds_budget","recovery_rate","recovery_min_stamina"]:
			var value: float=float(gate.get(key,1.0 if key.ends_with("scale") else 0.0))
			if not is_finite(value) or value<0.0: return false
		if gate.get("recovery_max_velocity")!=null and (not is_finite(float(gate.recovery_max_velocity)) or float(gate.recovery_max_velocity)<0.0): return false
		intervals.append(gate)
	intervals.append_array(candidate.get("connection_layout",[]))
	for interval: Dictionary in intervals:
		var start: float=float(interval.get("start_m",-1))
		var finish: float=float(interval.get("end_m",-1))
		var angle: float=float(interval.get("angle_degrees",0.0))
		if not is_finite(start) or not is_finite(finish) or start<250.0 or finish>1000.0 or start>=finish or not is_finite(angle) or angle<0.0 or angle>45.0: return false
		if str(interval.get("surface","STONE")) not in ["STONE","SOIL","GRAVEL","MUD","WET_STONE"]: return false
	for a: int in range(intervals.size()):
		for b: int in range(a):
			if float(intervals[a].start_m)<float(intervals[b].end_m) and float(intervals[b].start_m)<float(intervals[a].end_m): return false
	return true

func supports_entry_fixture() -> bool:
	return false

func identifiers(job: Dictionary,seed_value: int,campaign_id: String) -> Dictionary:
	var result: Dictionary=super.identifiers(job,seed_value,campaign_id)
	for key: String in ["ablation_stat","ablation_reference","purchase_mode"]:
		if job.has(key): result[key]=job[key]
	return result

func decide(boulder: BoulderController,policy: Dictionary,memory: Dictionary,rng: RandomNumberGenerator,name: String) -> Array:
	if name not in ["regular_recovery","skilled_recovery"]: return super.decide(boulder,policy,memory,rng,name)
	# Current observations and past released-input response only; no force,
	# gate location, future terrain, or hidden quota access.
	var fraction: float=boulder.stamina/boulder.max_stamina
	var shelf: bool=boulder.mountain.is_shelf(boulder.distance)
	if bool(memory.get("last_released",false)) and boulder.stamina<=float(memory.get("last_stamina",0.0))+0.001:
		memory.recovery_cooldown=boulder.elapsed+float(policy.recovery_retry_seconds)
	if shelf and fraction<float(policy.shelter_enter_below): memory.resting=true
	if not shelf or (fraction>=float(policy.shelter_recover_to) and absf(boulder.velocity)<=0.05): memory.resting=false
	var command: Array
	if bool(memory.get("resting",false)):
		command=[false,false,false]
	elif boulder.velocity<float(policy.brace_velocity) and boulder.stamina>0.0:
		command=[false,false,true]
	elif boulder.slip_remaining>0.0:
		command=[false,false,boulder.velocity < -0.03]
	else:
		var release: bool=not shelf and fraction<float(policy.recovery_stamina_threshold) and boulder.velocity>float(policy.recovery_release_velocity) and boulder.elapsed>=float(memory.get("recovery_cooldown",0.0))
		command=[not release,not release and boulder.velocity<float(policy.recovery_exert_velocity),false]
	if rng.randf()<float(policy.error_probability):
		command=[[false,false,false],[true,true,false],[false,false,true]][rng.randi_range(0,2)]
	memory.last_released=not bool(command[0]) and not bool(command[2]) and not shelf
	memory.last_stamina=boulder.stamina
	return command

func augment_result(result: Dictionary,controller: BoulderController,job: Dictionary) -> void:
	super.augment_result(result,controller,job)
	result.gate_telemetry=controller.gate_ledger.values().duplicate(true)
	result.experimental_environment="Finite released recovery opportunity time; not a slab or new character stat"
