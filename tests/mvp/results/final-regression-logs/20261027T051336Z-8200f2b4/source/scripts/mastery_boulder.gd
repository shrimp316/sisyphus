class_name MasteryBoulder
extends BoulderController

const Effects = preload("res://scripts/mastery_effects.gd")
var effects = Effects.new()
var mastery_effects: Dictionary = {}
var purchased_mastery_nodes: Array = []
var ability: Dictionary = {
	"exert_hold":0.0,"was_exerting":false,"burst_seconds":0.0,"burst_cooldown":0.0,
	"inertia_progress":0.0,"inertia_frontier":0.0,"inertia_ready":false,"inertia_seconds":0.0,"inertia_budget":0.0,
	"exhaustion_rescue_used":false,"reserve_charge":0,"rest_seconds":0.0,"rest_shelf":"",
	"reserve_shelves":{},"departure_shelves":{},"departure_remaining":0.0,"retreat_distance":0.0,
	"inertia_activations":0,"inertia_recovered":0.0,"brake_reductions":0,"reserve_uses":0
}

func apply_mastery_effects(modifiers: Dictionary) -> void:
	var previous_inertia: float = effects.amount("inertia_recovery_rate")
	effects.configure(modifiers)
	mastery_effects = effects.values.duplicate(true)
	purchased_mastery_nodes = modifiers.get("purchased_nodes", []).duplicate()
	push_multiplier = 1.0 + effects.amount("push_bonus")
	max_stamina = 100.0 * (1.0 + effects.amount("capacity_bonus"))
	recovery_multiplier = 1.0 + effects.amount("recovery_bonus")
	stamina = clampf(stamina, 0.0, max_stamina)
	if previous_inertia <= 0.0 and effects.amount("inertia_recovery_rate") > 0.0:
		ability.inertia_frontier = maxf(peak, distance)
	if effects.amount("post_exert_push_bonus") <= 0.0:
		ability.exert_hold = 0.0
		ability.was_exerting = false
		ability.burst_seconds = 0.0
	if effects.amount("inertia_recovery_rate") <= 0.0:
		ability.inertia_progress = 0.0
		ability.inertia_ready = false
		ability.inertia_seconds = 0.0
		ability.inertia_budget = 0.0

func _low_stamina_efficiency() -> float:
	return effects.amount("low_stamina_push_multiplier", 0.65)

func _exert_force_multiplier() -> float:
	return effects.amount("exert_multiplier", 1.65)

func _sweet_force_multiplier() -> float:
	return effects.amount("sweet_push_multiplier", 1.1)

func _starting_requirement() -> float:
	return effects.amount("start_requirement", 1.25)

func _additional_push_multiplier(exert: bool) -> float:
	return 1.0 + (effects.amount("post_exert_push_bonus") if not exert and float(ability.burst_seconds) > 0.0 else 0.0)

func _slip_decay_rate(rate: float, exert: bool, pushing: bool) -> float:
	return rate * (1.0 + effects.amount("non_exert_slip_decay_bonus")) if not (exert and pushing) else rate

func _stamina_drain_rate(rate: float, exert: bool, sweet: bool, bracing: bool) -> float:
	return rate * effects.drain_factor(exert, sweet, bracing, velocity < 0.0, stamina <= max_stamina * 0.2, float(ability.departure_remaining) > 0.0)

func _stamina_recovery_rate(rate: float, degrees: float, _safe: bool) -> float:
	return effects.recovery_rate(rate, degrees, velocity)

func _ledge_effective_push(force: float) -> float:
	return force * (1.0 + effects.amount("ledge_push_bonus"))

func _step(dt: float, push: bool, exert: bool, brace: bool) -> void:
	var active: bool = state == "climbing" and velocity > RUNAWAY_THRESHOLD and mountain.generation_version >= 3
	var before: Dictionary = {"distance":distance,"velocity":velocity,"stamina":stamina,"slips":slips,"safe":mountain.is_shelf(distance)}
	if active: _prepare_abilities(dt,push,exert,brace)
	super._step(dt,push,exert,brace)
	if active: _finish_abilities(dt,push,exert,brace,before)

func _prepare_abilities(dt: float, push: bool, exert: bool, brace: bool) -> void:
	ability.burst_cooldown = maxf(0.0,float(ability.burst_cooldown)-dt)
	var exerting: bool = push and exert and not brace and stamina>0.0 and slip_remaining<=0.0
	if effects.amount("post_exert_push_bonus")>0.0:
		if bool(ability.was_exerting) and not exerting and push and not exert and not brace and stamina>0.0 and slip_remaining<=0.0 and float(ability.exert_hold)>=0.4-0.000000001 and float(ability.burst_cooldown)<=0.0:
			ability.burst_seconds=0.5
			ability.burst_cooldown=2.0
		ability.exert_hold=float(ability.exert_hold)+dt if exerting else 0.0
	ability.was_exerting=exerting
	if effects.amount("inertia_recovery_rate")>0.0 and bool(ability.inertia_ready) and not push and not brace and velocity>0.0:
		ability.inertia_ready=false
		ability.inertia_seconds=1.0
		ability.inertia_budget=2.0
		ability.inertia_activations+=1

func _finish_abilities(dt: float, push: bool, exert: bool, brace: bool, before: Dictionary) -> void:
	ability.burst_seconds=maxf(0.0,float(ability.burst_seconds)-dt)
	# Abilities cannot revive Runaway, move the stone, or cancel a Slip lock.
	if state != "climbing": return
	var released: bool = not push and not brace
	# Observe the core's positive-to-zero transition before any other recovery.
	if float(before.stamina)>0.0 and stamina<=0.0:
		if effects.amount("exhaustion_rescue_fraction")>0.0 and not bool(ability.exhaustion_rescue_used):
			ability.exhaustion_rescue_used=true
			stamina=max_stamina*effects.amount("exhaustion_rescue_fraction")
		elif effects.amount("special_crisis_reserve_fraction")>0.0 and int(ability.reserve_charge)>0:
			ability.reserve_charge=0
			ability.reserve_uses+=1
			stamina=max_stamina*effects.amount("special_crisis_reserve_fraction")
	var movement: float = maxf(0.0,distance-float(before.distance))
	var frontier: float = maxf(float(ability.inertia_frontier),float(before.distance))
	var new_distance: float = maxf(0.0,distance-frontier)
	ability.inertia_frontier=maxf(frontier,distance)
	if effects.amount("inertia_recovery_rate")>0.0:
		if float(ability.inertia_seconds)>0.0:
			if released and velocity>0.0:
				var amount: float=minf(float(ability.inertia_budget),minf(2.0*minf(dt,float(ability.inertia_seconds)),max_stamina-stamina))
				stamina+=amount
				ability.inertia_budget=maxf(0.0,float(ability.inertia_budget)-amount)
				ability.inertia_recovered+=amount
			ability.inertia_seconds=maxf(0.0,float(ability.inertia_seconds)-dt)
		elif not bool(ability.inertia_ready):
			if float(before.velocity)>=0.45 and float(before.velocity)<=1.2 and velocity>0.0 and slips==int(before.slips):
				ability.inertia_progress+=new_distance
				if float(ability.inertia_progress)>=5.0:
					ability.inertia_progress=0.0
					ability.inertia_ready=true
			else:
				ability.inertia_progress=0.0
	var backward: float=maxf(0.0,float(before.distance)-distance)
	ability.retreat_distance+=backward
	if effects.amount("special_brake_slip_reduction")>0.0 and float(ability.retreat_distance)>=1.0 and brace and float(before.velocity)<0.0 and float(before.stamina)>0.0 and velocity==0.0 and float(before.velocity)+acceleration*dt>=0.0 and slips==int(before.slips):
		slip=maxf(0.0,slip-effects.amount("special_brake_slip_reduction"))
		ability.brake_reductions+=1
	if velocity>=0.0: ability.retreat_distance=0.0
	ability.departure_remaining=maxf(0.0,float(ability.departure_remaining)-movement)
	_update_shelf_preparation(dt,released)
	stamina=clampf(stamina,0.0,max_stamina)

func _update_shelf_preparation(dt: float, released: bool) -> void:
	if not released or not mountain.is_shelf(distance) or absf(velocity)>0.05:
		ability.rest_seconds=0.0
		ability.rest_shelf=""
		return
	var shelf: Dictionary=mountain.segment_at(distance)
	var key: String="%.6f:%.6f"%[float(shelf.start),float(shelf.end)]
	if str(ability.rest_shelf)!=key:
		ability.rest_shelf=key
		ability.rest_seconds=0.0
	ability.rest_seconds+=dt
	if float(ability.rest_seconds)<2.0-0.000000001: return
	if effects.amount("special_crisis_reserve_fraction")>0.0 and int(ability.reserve_charge)==0 and not ability.reserve_shelves.has(key):
		ability.reserve_charge=1
		ability.reserve_shelves[key]=true
	if effects.amount("special_departure_drain_reduction")>0.0 and not ability.departure_shelves.has(key):
		ability.departure_remaining=10.0
		ability.departure_shelves[key]=true

func get_run_ability_charges() -> Dictionary:
	return {"bre10_used":ability.exhaustion_rescue_used,"spc02_charge":ability.reserve_charge,"bre07_ready":ability.inertia_ready,"spc05_remaining_m":ability.departure_remaining}

func get_run_ability_cooldowns() -> Dictionary:
	return {"str10_seconds":ability.burst_seconds,"str10_cooldown":ability.burst_cooldown,"bre07_seconds":ability.inertia_seconds}

func snapshot() -> Dictionary:
	var result: Dictionary=super.snapshot()
	result.mastery_run=ability.duplicate(true)
	return result

func restore(data: Dictionary) -> void:
	super.restore(data)
	var saved: Dictionary=data.get("mastery_run",{}) if data.get("mastery_run",{}) is Dictionary else {}
	for key: String in ability:
		if not saved.has(key): continue
		var value: Variant=saved[key]
		if ability[key] is bool and value is bool: ability[key]=value
		elif ability[key] is String and value is String: ability[key]=value
		elif ability[key] is Dictionary and value is Dictionary: ability[key]=value.duplicate(true)
		elif (ability[key] is float or ability[key] is int) and (value is float or value is int) and is_finite(float(value)) and float(value)>=0.0:
			ability[key]=int(value) if ability[key] is int else float(value)
	ability.reserve_charge=clampi(int(ability.reserve_charge),0,1)
	ability.inertia_budget=clampf(float(ability.inertia_budget),0.0,2.0)
	ability.inertia_seconds=clampf(float(ability.inertia_seconds),0.0,1.0)
	ability.burst_seconds=clampf(float(ability.burst_seconds),0.0,0.5)
	ability.burst_cooldown=clampf(float(ability.burst_cooldown),0.0,2.0)
	ability.departure_remaining=clampf(float(ability.departure_remaining),0.0,10.0)
	ability.inertia_frontier=maxf(float(ability.inertia_frontier),peak)
