extends "res://scripts/mastery_boulder.gd"

# Finite ENVIRONMENTAL recovery. Purchased abilities remain active after this
# quota ends, so its80-unit budget is not an upper bound on all mastery recovery.
var opportunity_remaining: float = 80.0 / 7.0
var opportunity_used: float = 0.0
var environmental_recovered: float = 0.0
var core_recovery_total: float = 0.0
var gate_entries: Array = []
var gate_exit: Dictionary = {}
var _inside: bool = false
var _released: bool = false
var _step_dt: float = FIXED_DT

func _step(dt: float, push: bool, exert: bool, brace: bool) -> void:
	_step_dt = dt
	_released = not push and not brace
	var inside: bool = distance >= 750.0 and distance < 940.0 and state == "climbing"
	if inside and not _inside:
		gate_entries.append({"seconds":elapsed,"distance":distance,"velocity":velocity,"stamina":stamina,"opportunity_remaining":opportunity_remaining})
	_inside = inside
	super._step(dt,push,exert,brace)
	if inside and distance >= 940.0 and gate_exit.is_empty():
		gate_exit = {"seconds":elapsed,"distance":distance,"velocity":velocity,"stamina":stamina}

func _stamina_recovery_rate(rate: float, degrees: float, safe: bool) -> float:
	if not _inside or safe:
		return super._stamina_recovery_rate(rate,degrees,safe)
	var environment_rate: float = 0.0
	if _released and stamina >= 1.0:
		var eligible_dt: float = minf(_step_dt,opportunity_remaining)
		opportunity_remaining = maxf(0.0,opportunity_remaining-eligible_dt)
		opportunity_used += eligible_dt
		environment_rate = 7.0*eligible_dt/_step_dt
	var modified_rate: float = super._stamina_recovery_rate(environment_rate,degrees,safe)
	if _released:
		var room: float = maxf(0.0,max_stamina-stamina)
		environmental_recovered += minf(room,environment_rate*recovery_multiplier*_step_dt)
		core_recovery_total += minf(room,modified_rate*recovery_multiplier*_step_dt)
	return modified_rate

func experiment_snapshot() -> Dictionary:
	return {"opportunity_remaining":opportunity_remaining,"opportunity_used":opportunity_used,"environmental_recovered":environmental_recovered,"core_recovery_total":core_recovery_total,"gate_entries":gate_entries.duplicate(true),"gate_exit":gate_exit.duplicate(true),"ability":ability.duplicate(true)}
