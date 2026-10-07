class_name BoulderController
extends RefCounted

signal started_falling
signal recovered
signal runaway_started
signal reached_distance(distance: float)
signal ledge_crossed(distance: float)

const FIXED_DT: float = 1.0 / 120.0
const MAX_SPEED: float = 2.5
const RUNAWAY_THRESHOLD: float = -4.0
const V02_MAX_SPEED: float = 1.8
const BASE_PUSH: float = 2.6
const GRAVITY: float = 3.0
var mountain: MountainManager
var distance: float = 0.0
var velocity: float = 0.0
var acceleration: float = 0.0
var stamina: float = 100.0
var slip: float = 0.0
var slip_remaining: float = 0.0
var peak: float = 0.0
var elapsed: float = 0.0
var state: String = "climbing"
var action: String = "rest"
var slips: int = 0
var accumulator: float = 0.0
var runaway_elapsed: float = 0.0
var partial_falls: int = 0
var cleared_ledges: Dictionary = {}
var falling_active: bool = false
var push_force: float = 0.0
var gravity_force: float = 0.0
var surface_resistance: float = 0.0
var momentum: float = 1.0
var control_multiplier: float = 1.0
var ledge_blocked: bool = false

func _init(terrain: MountainManager = null) -> void:
	mountain = terrain if terrain != null else MountainManager.new()

func stamina_multiplier() -> float:
	if stamina >= 50.0:
		return 1.0
	if stamina >= 20.0:
		return 0.85
	if stamina > 0.0:
		return 0.65
	return 0.45 if mountain.generation_version >= 3 else 0.5

func rollback_stage() -> String:
	if mountain.generation_version >= 3:
		return ["", "밀림", "후퇴 · Space로 버티기", "추락 · 지금 버티세요", "폭주"][fall_stage()]
	if state == "runaway":
		return "폭주"
	if velocity < -1.0:
		return "후퇴 · Space로 버티기"
	if velocity < -0.08:
		return "흔들림"
	return ""

func advance(delta: float, push: bool, exert: bool, brace: bool) -> void:
	# Fixed substeps make simulation invariant to rendering/frame rate.
	accumulator += maxf(delta, 0.0)
	while accumulator + 0.00000001 >= FIXED_DT:
		accumulator -= FIXED_DT
		_step(FIXED_DT, push, exert and push, brace)
	if absf(accumulator) < 0.00000001:
		accumulator = 0.0

func _step(dt: float, push: bool, exert: bool, brace: bool) -> void:
	if mountain.generation_version >= 3:
		_step_v02(dt, push, exert, brace)
	else:
		_step_legacy(dt, push, exert, brace)

func _step_legacy(dt: float, push: bool, exert: bool, brace: bool) -> void:
	if state == "result" or state == "summit":
		return
	elapsed += dt
	if state == "runaway":
		runaway_elapsed += dt
		velocity = maxf(velocity - 9.0 * dt, -65.0)
		distance = maxf(0.0, distance + velocity * dt)
		if distance <= 0.0:
			finish_fall()
		return
	var angle: float = mountain.angle_at(distance)
	var gravity: float = 4.0 * sin(angle)
	var resisting: float = mountain.resistance_at(distance)
	var grip: float = mountain.grip_at(distance)
	var slipping: bool = slip_remaining > 0.0
	slip_remaining = maxf(0.0, slip_remaining - dt)
	var braking: bool = brace and velocity < 0.0 and not slipping
	var pushing: bool = push and not brace and not slipping
	var force: float = 2.0 * stamina_multiplier() * grip * (1.65 if exert else 1.0) if pushing else 0.0
	push_force = force
	gravity_force = gravity
	surface_resistance = resisting
	acceleration = force - gravity
	if absf(velocity) > 0.01:
		acceleration -= signf(velocity) * resisting
	elif absf(acceleration) <= resisting:
		acceleration = 0.0
	else:
		acceleration -= signf(acceleration) * resisting
	if braking:
		acceleration += 5.8 * stamina_multiplier() * grip
		stamina -= 5.5 * dt
		action = "brace"
	elif brace and angle > 0.0 and not slipping:
		# Keeping a braced stance costs effort even on the frame we stop.
		# Otherwise alternating tiny backward/zero steps regenerates stamina.
		stamina -= 5.5 * dt
		action = "brace"
	elif pushing:
		stamina -= (0.75 + rad_to_deg(angle) / 35.0) * (3.0 if exert else 1.0) * dt
		action = "exert" if exert else "push"
	else:
		stamina += (8.0 if absf(velocity) < 0.05 else 5.0) * dt
		action = "slip" if slipping else "rest"
	stamina = clampf(stamina, 0.0, 100.0)
	if pushing and angle > 0.01:
		slip += (rad_to_deg(angle) / 35.0) * (3.8 if exert else 0.85) * mountain.slip_multiplier_at(distance) * dt
	else:
		slip = maxf(0.0, slip - 9.0 * dt)
	if slip >= 100.0:
		slip = 0.0
		slip_remaining = 1.0
		slips += 1
	var old_velocity: float = velocity
	velocity = clampf(velocity + acceleration * dt, -65.0, MAX_SPEED)
	# A brake can stop a retreat, never propel the stone uphill.
	if braking and velocity > 0.0:
		velocity = 0.0
	if not pushing and mountain.is_shelf(distance) and old_velocity > 0.0 and velocity < 0.0:
		velocity = 0.0
	if not mountain.legacy and not pushing and mountain.is_shelf(distance) and (old_velocity * velocity <= 0.0 or absf(velocity) <= 0.01):
		velocity = 0.0
	distance = maxf(0.0, distance + velocity * dt)
	peak = maxf(peak, distance)
	if distance <= 0.0:
		velocity = maxf(0.0, velocity)
	if velocity < RUNAWAY_THRESHOLD:
		state = "runaway"
	if distance >= MountainManager.LENGTH:
		distance = MountainManager.LENGTH
		peak = MountainManager.LENGTH
		velocity = 0.0
		state = "summit"

func finish_fall() -> void:
	distance = 0.0
	velocity = 0.0
	state = "result"

func snapshot() -> Dictionary:
	return {"distance": distance, "velocity": velocity, "stamina": stamina, "slip": slip, "slip_remaining": slip_remaining, "peak": peak, "elapsed": elapsed, "state": state, "slips": slips, "accumulator": accumulator, "runaway_elapsed": runaway_elapsed, "partial_falls": partial_falls, "cleared_ledges": cleared_ledges.duplicate(), "falling_active": falling_active}

func restore(data: Dictionary) -> void:
	distance = clampf(float(data.get("distance", 0.0)), 0.0, mountain.total_length)
	velocity = clampf(float(data.get("velocity", 0.0)), -65.0, V02_MAX_SPEED if mountain.generation_version >= 3 else MAX_SPEED)
	stamina = clampf(float(data.get("stamina", 100.0)), 0.0, 100.0)
	slip = clampf(float(data.get("slip", 0.0)), 0.0, 99.999)
	slip_remaining = clampf(float(data.get("slip_remaining", 0.0)), 0.0, 1.0)
	peak = clampf(float(data.get("peak", distance)), distance, mountain.total_length)
	elapsed = maxf(0.0, float(data.get("elapsed", 0.0)))
	slips = maxi(0, int(data.get("slips", 0)))
	state = str(data.get("state", "climbing"))
	if state not in ["climbing", "runaway", "result", "summit"]:
		state = "climbing"
	accumulator = clampf(float(data.get("accumulator", 0.0)), 0.0, FIXED_DT)
	runaway_elapsed = maxf(0.0, float(data.get("runaway_elapsed", 0.0)))
	partial_falls = maxi(0, int(data.get("partial_falls", 0)))
	cleared_ledges = (data.get("cleared_ledges", {}) as Dictionary).duplicate()
	falling_active = bool(data.get("falling_active", velocity < 0.0))

func fall_stage() -> int:
	if state == "runaway" or velocity <= -4.0:
		return 4
	if velocity <= -2.0:
		return 3
	if velocity <= -0.8:
		return 2
	return 1 if velocity < 0.0 else 0

func speed_band() -> String:
	if velocity < 0.0:
		return "후퇴"
	if velocity < 0.15:
		return "정지"
	if velocity < 0.45:
		return "저속"
	if velocity <= 1.2:
		return "적정"
	return "위험" if velocity > 1.7 else "고속"

func telemetry() -> Dictionary:
	return {"distance": distance, "velocity": velocity, "acceleration": acceleration, "slope": rad_to_deg(mountain.angle_at(distance)), "push_force": push_force, "gravity_force": gravity_force, "resistance": surface_resistance, "momentum": momentum, "control_multiplier": control_multiplier, "stamina": stamina, "slip": slip, "surface": str(mountain.surface_at(distance).id), "run_state": state, "speed_band": speed_band(), "fall_stage": fall_stage(), "ledge_blocked": ledge_blocked}

func slope_drain_multiplier(angle_degrees: float) -> float:
	if angle_degrees <= 10.0:
		return 0.8
	if angle_degrees <= 20.0:
		return lerpf(0.8, 1.0, (angle_degrees - 10.0) / 10.0)
	if angle_degrees <= 30.0:
		return lerpf(1.0, 1.3, (angle_degrees - 20.0) / 10.0)
	return lerpf(1.3, 1.7, clampf((angle_degrees - 30.0) / 10.0, 0.0, 1.0))

func _step_v02(dt: float, push: bool, exert: bool, brace: bool) -> void:
	if state in ["result", "summit"]:
		return
	elapsed += dt
	if state == "runaway":
		runaway_elapsed += dt
		velocity = maxf(velocity - 9.0 * dt, -65.0)
		distance = maxf(0.0, distance + velocity * dt)
		if distance <= 0.0:
			finish_fall()
		return
	# Once this boundary is crossed, no groove can catch the stone.
	if velocity <= RUNAWAY_THRESHOLD:
		_enter_runaway()
		return
	var old_distance: float = distance
	var old_velocity: float = velocity
	var angle: float = mountain.angle_at(distance)
	var degrees: float = rad_to_deg(angle)
	var material: Dictionary = mountain.surface_at(distance)
	var grip: float = mountain.grip_at(distance)
	var safe: bool = mountain.is_shelf(distance)
	var sweet: bool = velocity >= 0.45 and velocity <= 1.2
	var starting: bool = velocity >= 0.0 and velocity <= 0.15
	var slipping: bool = slip_remaining > 0.0
	var pushing: bool = push and not brace
	var braking: bool = brace and velocity < 0.0 and not slipping
	var braced_stance: bool = brace and angle > 0.0 and not slipping
	slip_remaining = maxf(0.0, slip_remaining - dt)
	momentum = 1.1 if sweet else 1.0
	control_multiplier = 0.9 if velocity > 1.5 else 1.0
	push_force = BASE_PUSH * stamina_multiplier() * grip * (1.65 if exert else 1.0) * momentum * control_multiplier if pushing else 0.0
	if slipping:
		push_force *= 0.1
	gravity_force = GRAVITY * sin(angle)
	surface_resistance = mountain.resistance_at(distance)
	if str(material.id) == "MUD":
		surface_resistance *= 1.0 + clampf((0.45 - absf(velocity)) / 0.45, 0.0, 1.0)
	var requirement: float = 1.25 if starting and pushing else 1.0
	var net: float = push_force - gravity_force * requirement
	if absf(velocity) > 0.001:
		acceleration = net - signf(velocity) * surface_resistance * requirement
	else:
		acceleration = signf(net) * maxf(0.0, absf(net) - surface_resistance * requirement)
	if braking:
		acceleration += 5.8 * stamina_multiplier() * grip
	var drain_multiplier: float = slope_drain_multiplier(degrees)
	if braking or braced_stance:
		stamina -= 4.0 * drain_multiplier * dt
		action = "brace"
	elif pushing:
		stamina -= (3.0 if exert else 1.0) * drain_multiplier * (0.8 if sweet else 1.0) * dt
		action = "slip" if slipping else ("exert" if exert else "push")
	else:
		var recovery: float = 10.0 if safe else (7.0 if absf(velocity) < 0.01 else (3.0 if degrees <= 10.0 else 0.0))
		stamina += recovery * dt
		action = "slip" if slipping else "rest"
	stamina = clampf(stamina, 0.0, 100.0)
	var slip_gain: float = 0.0
	if pushing and not slipping:
		slip_gain = 4.0 * degrees / 35.0 * mountain.slip_multiplier_at(distance) * (1.8 if exert else 1.0)
		if exert and str(material.id) == "GRAVEL":
			slip_gain *= 1.3
		slip_gain *= 0.9 if sweet else (1.4 if velocity > 1.5 else 1.0)
	var slip_recovery: float = 20.0 if safe else (10.0 if absf(velocity) < 0.01 else (4.0 if not exert else 0.0))
	slip = clampf(slip + (slip_gain - slip_recovery) * dt, 0.0, 100.0)
	if slip >= 100.0:
		slip = 0.0
		slip_remaining = 0.7
		slips += 1
	velocity = clampf(velocity + acceleration * dt, -65.0, V02_MAX_SPEED)
	if braking and velocity > 0.0:
		velocity = 0.0
	if safe and not pushing and (old_velocity * velocity <= 0.0 or absf(velocity) < 0.002):
		velocity = 0.0
	distance = maxf(0.0, distance + velocity * dt)
	if velocity <= RUNAWAY_THRESHOLD:
		_enter_runaway()
	else:
		_resolve_ledges(old_distance)
		if velocity < 0.0:
			for rest_point: float in mountain.rest_points:
				if old_distance > rest_point and distance <= rest_point:
					distance = rest_point
					velocity = 0.0
					partial_falls += 1
					if not falling_active:
						falling_active = true
					break
	if velocity < 0.0 and not falling_active:
		falling_active = true
		started_falling.emit()
	elif velocity >= 0.0 and falling_active and state != "runaway":
		falling_active = false
		recovered.emit()
	if distance <= 0.0:
		velocity = maxf(0.0, velocity)
	if distance > peak:
		peak = minf(distance, mountain.total_length)
		reached_distance.emit(peak)
	if distance >= mountain.total_length:
		distance = mountain.total_length
		peak = mountain.total_length
		velocity = 0.0
		state = "summit"

func _enter_runaway() -> void:
	state = "runaway"
	runaway_elapsed = 0.0
	runaway_started.emit()

func _resolve_ledges(old_distance: float) -> void:
	ledge_blocked = false
	for ledge: Dictionary in mountain.ledges:
		var position: float = float(ledge.distance)
		var id: String = str(ledge.id)
		if distance < position - 0.75:
			cleared_ledges.erase(id)
		if old_distance <= position and distance > position and not bool(cleared_ledges.get(id, false)):
			var required: float = BASE_PUSH * mountain.grip_at(position) * float(ledge.required_push)
			if push_force + 0.00001 >= required:
				cleared_ledges[id] = true
				velocity *= 0.88
				ledge_crossed.emit(position)
			else:
				distance = position - 0.02
				velocity = -0.05
				ledge_blocked = true
