extends "res://tests/balance/adjustment_v02/observed_controller.gd"

# Test-only environmental opportunity time, never a new character capacity.
# Eligible released-input time is consumed even at full stamina.
var gate_ledger: Dictionary = {}
var active_gate_id: String = ""
var _gate_before: Dictionary = {}
var _eligible_this_step: bool = false

func gate_at(position: float) -> Dictionary:
	for gate: Dictionary in experiment.get("gates", []):
		if position >= float(gate.start_m) and position < float(gate.end_m): return gate
	return {}

func gate_scale(key: String) -> float:
	return float(gate_at(distance).get(key, 1.0))

func _gate_before_step(dt: float, push: bool, exert: bool, brace: bool) -> void:
	_eligible_this_step = false
	var gate: Dictionary = gate_at(distance)
	var next_id: String = str(gate.get("id", ""))
	if active_gate_id!=next_id and gate_ledger.has(active_gate_id): gate_ledger[active_gate_id].eligible_last_step=false
	if not next_id.is_empty():
		if not gate_ledger.has(next_id):
			var seconds: float = float(gate.get("recovery_seconds_budget", 0.0))
			gate_ledger[next_id] = {"id":next_id,"entry_seconds":elapsed,"entry_stamina":stamina,"entry_velocity":velocity,"entry_recovery_multiplier":recovery_multiplier,"seconds_budget":seconds,"seconds_remaining":seconds,"seconds_used":0.0,"amount_upper_bound_at_entry":seconds*float(gate.get("recovery_rate",0.0))*recovery_multiplier,"recovered_amount":0.0,"recovery_events":0,"eligible_last_step":false,"entries":0,"entry_history":[],"passed":false,"exit_seconds":null,"exit_stamina":null,"push_seconds":0.0,"exert_seconds":0.0,"brace_seconds":0.0,"released_seconds":0.0,"slips":0,"exhaustion_episodes":0,"runaways":0,"minimum_stamina":stamina}
		var ledger: Dictionary = gate_ledger[next_id]
		if active_gate_id != next_id:
			ledger.entries += 1
			ledger.entry_history.append({"seconds":elapsed,"distance_m":distance,"stamina":stamina,"velocity":velocity,"remaining_seconds":ledger.seconds_remaining})
		ledger.push_seconds += dt if push and not exert and not brace else 0.0
		ledger.exert_seconds += dt if push and exert and not brace else 0.0
		ledger.brace_seconds += dt if brace else 0.0
		ledger.released_seconds += dt if not push and not brace else 0.0
	active_gate_id = next_id
	_gate_before = {"id":next_id,"stamina":stamina,"slips":slips,"gate":gate,"released":not push and not brace}

func _gate_recovery_amount(original_rate: float, dt: float, effort_requested: bool, safe: bool) -> float:
	var gate: Dictionary = gate_at(distance)
	if gate.is_empty() or safe:
		return original_rate * recovery_multiplier * dt
	if effort_requested or not bool(_gate_before.get("released",false)): return 0.0
	var maximum: Variant = gate.get("recovery_max_velocity", null)
	if maximum != null and absf(velocity) > float(maximum): return 0.0
	if stamina < float(gate.get("recovery_min_stamina",0.0)): return 0.0
	var ledger: Dictionary = gate_ledger[str(gate.id)]
	var eligible_dt: float = minf(dt,float(ledger.seconds_remaining))
	if eligible_dt <= 0.0: return 0.0
	_eligible_this_step = true
	ledger.seconds_remaining = maxf(0.0,float(ledger.seconds_remaining)-eligible_dt)
	ledger.seconds_used += eligible_dt
	var amount: float = minf(maxf(0.0,max_stamina-stamina),float(gate.get("recovery_rate",0.0))*recovery_multiplier*eligible_dt)
	ledger.recovered_amount += amount
	return amount

func _gate_after_step() -> void:
	var id: String = str(_gate_before.get("id", ""))
	if id.is_empty(): return
	var ledger: Dictionary = gate_ledger[id]
	ledger.recovery_events += 1 if _eligible_this_step and not bool(ledger.eligible_last_step) else 0
	ledger.eligible_last_step = _eligible_this_step
	ledger.slips += slips-int(_gate_before.slips)
	ledger.exhaustion_episodes += 1 if stamina<=0.0 and float(_gate_before.stamina)>0.0 else 0
	ledger.runaways += 1 if state=="runaway" else 0
	ledger.minimum_stamina = minf(float(ledger.minimum_stamina),stamina)
	if distance >= float(_gate_before.gate.end_m) and not bool(ledger.passed):
		ledger.passed = true
		ledger.exit_seconds = elapsed
		ledger.exit_stamina = stamina
		ledger.exit_velocity = velocity

func snapshot() -> Dictionary:
	var result: Dictionary = super.snapshot()
	result.gate_ledger = gate_ledger.duplicate(true)
	result.active_gate_id = active_gate_id
	return result

func restore(data: Dictionary) -> void:
	super.restore(data)
	gate_ledger = data.get("gate_ledger",{}).duplicate(true)
	active_gate_id = str(data.get("active_gate_id",""))
