extends "res://tests/balance/adjustment_v03/diagnostic.gd"

# Independent policy ablation only. Production/generated physics unchanged.
func decide(boulder: BoulderController,policy: Dictionary,memory: Dictionary,rng: RandomNumberGenerator,name: String) -> Array:
	var selected: Dictionary=policy
	if active_job.has("verification_cooldown_override"):
		selected=policy.duplicate(true)
		selected.recovery_retry_seconds=float(active_job.verification_cooldown_override)
	return super.decide(boulder,selected,memory,rng,name)
