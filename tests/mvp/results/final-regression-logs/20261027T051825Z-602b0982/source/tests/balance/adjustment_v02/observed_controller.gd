extends "res://tests/balance/balance_controller.gd"

# Instrumentation wraps the production fixed step. It never writes physical
# state, forces, slip values, or inputs. The generated subclass changes only
# the explicitly documented scalar coefficients inside the original function.
var experiment: Dictionary = {}
var stall_seconds: float = 45.0
var stall_progress_m: float = 0.25
var metrics: Dictionary = {"consumed": 0.0, "recovered": 0.0, "moving_shelf_recovery": 0.0, "stationary_shelf_recovery": 0.0, "exhausted_seconds": 0.0, "stamina_integral": 0.0, "active_seconds": 0.0, "recovery_episodes": 0, "push_seconds": 0.0, "exert_seconds": 0.0, "brace_seconds": 0.0}
var bands_200: Array = []
var bands_250: Array = []
var shelter_events: Array = []
var slip_events: Array = []
var rollback_events: Array = []
var stall_events: Array = []
var brace_episodes: int = 0
var _previous_brace: bool = false
var _previous_recovery: bool = false
var _shelter: Dictionary = {}
var _rollback: Dictionary = {}
var _last_progress: float = 0.0
var _progress_peak: float = 0.0
var _replay_state: Dictionary = {}
var _inputs: Array = []
var _active_stall: Dictionary = {}
var _death_distance: float = -1.0

func _init(world: MountainManager = null) -> void:
	super(world)
	for width: int in [200, 250]:
		var collection: Array = bands_200 if width == 200 else bands_250
		for index: int in range(1000 / width):
			collection.append({"index": index, "width_m": width, "entered": index == 0, "entry_seconds": 0.0 if index == 0 else null, "first_passage_seconds": null, "exposure_seconds": 0.0, "slips": 0, "runaways": 0, "exhaustion_episodes": 0, "death": false, "rollback_m": 0.0, "shelter_seconds": 0.0, "stamina_consumed": 0.0, "stamina_recovered": 0.0, "exhausted_seconds": 0.0, "stamina_integral": 0.0})

func _step(dt: float, push: bool, exert: bool, brace: bool) -> void:
	if _replay_state.is_empty():
		_replay_state = snapshot()
	_record_input(push, exert, brace)
	var before: Dictionary = {"state": state, "distance": distance, "stamina": stamina, "velocity": velocity, "slips": slips, "shelf": mountain.is_shelf(distance)}
	super._step(dt, push, exert, brace)
	if str(before.state) != "climbing":
		return
	var consumed: float = maxf(0.0, float(before.stamina) - stamina)
	var recovered_amount: float = maxf(0.0, stamina - float(before.stamina))
	metrics.consumed += consumed
	metrics.recovered += recovered_amount
	metrics.active_seconds += dt
	metrics.stamina_integral += float(before.stamina) * dt
	metrics.exhausted_seconds += dt if stamina <= 0.0 else 0.0
	metrics.recovery_episodes += 1 if recovered_amount > 0.0 and not _previous_recovery else 0
	_previous_recovery = recovered_amount > 0.0
	metrics.push_seconds += dt if push and not exert and not brace else 0.0
	metrics.exert_seconds += dt if push and exert and not brace else 0.0
	metrics.brace_seconds += dt if brace else 0.0
	if brace and not _previous_brace:
		brace_episodes += 1
	_previous_brace = brace
	for width: int in [200, 250]:
		var collection: Array = bands_200 if width == 200 else bands_250
		var band: Dictionary = collection[clampi(int(float(before.distance) / width), 0, collection.size() - 1)]
		band.exposure_seconds += dt
		band.stamina_consumed += consumed
		band.stamina_recovered += recovered_amount
		band.exhausted_seconds += dt if stamina <= 0.0 else 0.0
		band.stamina_integral += float(before.stamina) * dt
		band.rollback_m += maxf(0.0, float(before.distance) - distance)
		band.shelter_seconds += dt if bool(before.shelf) else 0.0
		band.slips += slips - int(before.slips)
		band.runaways += 1 if state == "runaway" else 0
		band.exhaustion_episodes += 1 if stamina <= 0.0 and float(before.stamina) > 0.0 else 0
		for index: int in range(collection.size()):
			if peak >= index * width and not collection[index].entered:
				collection[index].entered = true
				collection[index].entry_seconds = elapsed
			if peak >= (index + 1) * width and collection[index].first_passage_seconds == null:
				collection[index].first_passage_seconds = elapsed - float(collection[index].entry_seconds)
	if state == "runaway":
		_death_distance = float(before.distance)
	_shelter_metrics(before, recovered_amount, dt, not push and not brace)
	_risk_metrics(before, push, exert, brace)
	_stall_metrics(push, exert, brace)

func _record_input(push: bool, exert: bool, brace: bool) -> void:
	var command: Array = [push, exert, brace]
	var stats: Array = [push_multiplier, max_stamina, recovery_multiplier]
	if not _inputs.is_empty() and _inputs.back().command == command and _inputs.back().stats == stats:
		_inputs.back().steps += 1
	else:
		_inputs.append({"command": command, "stats": stats, "steps": 1})

func _shelter_metrics(before: Dictionary, recovered_amount: float, dt: float, released: bool) -> void:
	if bool(before.shelf):
		if _shelter.is_empty():
			_shelter = {"entry_seconds": elapsed - dt, "entry_m": before.distance, "entry_stamina": before.stamina, "exit_seconds": null, "exit_m": null, "exit_stamina": null, "moving_recovery": 0.0, "stationary_recovery": 0.0, "stationary_seconds": 0.0, "stationary_rest_seconds": 0.0}
		if absf(float(before.velocity)) > 0.05:
			metrics.moving_shelf_recovery += recovered_amount
			_shelter.moving_recovery += recovered_amount
		else:
			metrics.stationary_shelf_recovery += recovered_amount
			_shelter.stationary_recovery += recovered_amount
			_shelter.stationary_seconds += dt
			_shelter.stationary_rest_seconds += dt if released else 0.0
	if not _shelter.is_empty() and (not mountain.is_shelf(distance) or state != "climbing"):
		_shelter.exit_seconds = elapsed
		_shelter.exit_m = distance
		_shelter.exit_stamina = stamina
		shelter_events.append(_shelter)
		_shelter = {}

func _risk_metrics(before: Dictionary, push: bool, exert: bool, brace: bool) -> void:
	if slips > int(before.slips):
		slip_events.append({"seconds": elapsed, "distance_m": before.distance, "stamina": stamina, "velocity": velocity, "input": [push, exert, brace], "surface": mountain.surface_at(float(before.distance)).id, "outcome": "pending", "recovery_seconds": null})
	for event: Dictionary in slip_events:
		if event.outcome == "pending":
			if state == "runaway":
				event.outcome = "runaway"
				event.recovery_seconds = elapsed - float(event.seconds)
			elif velocity >= 0.0 and slip_remaining <= 0.0:
				event.outcome = "recovered"
				event.recovery_seconds = elapsed - float(event.seconds)
	if velocity < 0.0 and _rollback.is_empty():
		_rollback = {"seconds": elapsed, "distance_m": before.distance, "rollback_m": 0.0, "outcome": "pending", "recovery_seconds": null, "brace_used": false}
	if not _rollback.is_empty():
		_rollback.rollback_m += maxf(0.0, float(before.distance) - distance)
		_rollback.brace_used = bool(_rollback.brace_used) or brace
		if state == "runaway" or velocity >= 0.0:
			_rollback.outcome = "runaway" if state == "runaway" else "recovered"
			_rollback.recovery_seconds = elapsed - float(_rollback.seconds)
			rollback_events.append(_rollback)
			_rollback = {}

func _stall_metrics(push: bool, exert: bool, brace: bool) -> void:
	if peak >= _progress_peak + stall_progress_m:
		if not _active_stall.is_empty():
			_close_stall("progress_resumed")
		_progress_peak = peak
		_last_progress = elapsed
		_replay_state = snapshot()
		_inputs.clear()
	elif state == "climbing" and elapsed - _last_progress >= stall_seconds and _active_stall.is_empty():
		_active_stall = {"start_seconds": _last_progress, "detected_seconds": elapsed, "end_seconds": null, "distance_m": distance, "state": snapshot(), "input": [push, exert, brace], "replay_start_state": _replay_state.duplicate(true)}
	if state != "climbing" and not _active_stall.is_empty():
		_close_stall(state)

func _close_stall(outcome: String) -> void:
	_active_stall.end_seconds = elapsed
	_active_stall.duration_seconds = elapsed - float(_active_stall.start_seconds)
	_active_stall.outcome = outcome
	_active_stall.input_history = _inputs.duplicate(true)
	_active_stall.replay_end_state = snapshot()
	stall_events.append(_active_stall)
	_active_stall = {}

func finalize_metrics() -> Dictionary:
	if not _active_stall.is_empty():
		_close_stall("censored")
	if not _shelter.is_empty():
		_shelter.censored = true
		shelter_events.append(_shelter)
		_shelter = {}
	if not _rollback.is_empty():
		_rollback.outcome = "censored"
		rollback_events.append(_rollback)
		_rollback = {}
	for event: Dictionary in slip_events:
		if event.outcome == "pending":
			event.outcome = "censored"
	if state == "result" and _death_distance >= 0.0:
		bands_200[clampi(int(_death_distance / 200.0), 0, 4)].death = true
		bands_250[clampi(int(_death_distance / 250.0), 0, 3)].death = true
	metrics.mean_stamina = float(metrics.stamina_integral) / maxf(FIXED_DT, float(metrics.active_seconds))
	return {"stamina_metrics": metrics, "bands_200": bands_200, "v02_bands_250": bands_250, "shelter_events": shelter_events, "slip_events": slip_events, "rollback_events": rollback_events, "brace_episodes": brace_episodes, "stall_events": stall_events}
