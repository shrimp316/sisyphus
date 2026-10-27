extends "res://tests/mvp/difficulty_experiment.gd"
## New policy adaptation is separate from the unchanged-policy transfer experiment.
var neutral_rng := RandomNumberGenerator.new()

func policy_path() -> String:
	return "res://tests/mvp/difficulty_aware_policies.json"

func decide(stone: BoulderController, policy: Dictionary, memory: Dictionary, rng: RandomNumberGenerator, name: String) -> Array:
	var base_name: String = name.trim_suffix("_aware")
	var neutral: Dictionary = policy.duplicate()
	neutral.error_probability = 0.0
	# Preserve the original one error draw/decision on the live RNG.
	neutral_rng.state = rng.state
	var command: Array = super.decide(stone,neutral,memory,neutral_rng,base_name)
	var limit: float = float(policy.slip_limit)
	if stone.slip >= limit: memory.risk_resting = true
	if stone.slip <= maxf(0.0,limit-15.0): memory.risk_resting = false
	if bool(memory.get("risk_resting",false)):
		command = [false,false,stone.velocity < float(policy.brace_velocity) and stone.stamina>0.0]
	elif not stone.mountain.is_shelf(stone.distance) and stone.slip_remaining<=0.0:
		# The last visible metre of this slope is enough to enter an 8m shelf slowly.
		var current: Dictionary = stone.mountain.segment_at(stone.distance)
		var remaining: float = float(current.end)-stone.distance
		if remaining<=1.2 and stone.velocity>.5 and stone.stamina<stone.max_stamina*float(policy.shelter_recover_to):
			command = [false,false,false]
	if rng.randf()<float(policy.error_probability):
		command = [[false,false,false],[true,true,false],[false,false,true]][rng.randi_range(0,2)]
	return command
