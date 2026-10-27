extends "res://tests/balance/adjustment_v02/observed_controller.gd"

# GENERATED from production SHA256 30a312b144383be64fc6fe35b8ad107ebba9a90672d9dda941f9ef8018279944.
# Only three scalar sites are instrumented; do not edit this artifact.
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
	var has_stamina: bool = stamina > 0.0
	var effort_requested: bool = (push and not brace) or (brace and (angle > 0.0 or velocity < 0.0))
	var pushing: bool = push and not brace and not slipping and has_stamina
	var braking: bool = brace and velocity < 0.0 and has_stamina
	var braced_stance: bool = brace and angle > 0.0 and has_stamina
	slip_remaining = maxf(0.0, slip_remaining - dt)
	var slip_gain: float = 0.0
	if pushing:
		slip_gain = 4.0 * degrees / 35.0 * mountain.slip_multiplier_at(distance) * (1.8 if exert else 1.0)
		if exert and str(material.id) == "GRAVEL":
			slip_gain *= 1.3
		slip_gain *= 0.9 if sweet else (1.4 if velocity > 1.5 else 1.0)
	if distance >= 500.0:
		slip_gain *= float(experiment.get("slip_gain_after500_scale", 1.0))
	var slip_recovery: float = 20.0 if safe else (10.0 if absf(velocity) < 0.01 else (4.0 if not (exert and pushing) else 0.0))
	if not safe and distance >= 750.0:
		slip_recovery *= float(experiment.get("slip_decay_after750_scale", 1.0))
	slip = clampf(slip + (slip_gain - slip_recovery) * dt, 0.0, 100.0)
	if not slipping and slip >= 100.0:
		slip = 0.0
		slip_remaining = SLIP_DURATION
		slips += 1
		# Losing footing removes uphill momentum once, before this step's forces.
		# The impulse alone cannot cause runaway or rescue an already faster retreat.
		velocity = maxf(minf(velocity, 0.0) - SLIP_ROLLBACK_IMPULSE, minf(velocity, -SLIP_IMPULSE_SPEED_LIMIT))
		stamina = maxf(0.0, stamina - SLIP_STAMINA_COST)
		slipping = true
		pushing = false
		has_stamina = stamina > 0.0
		braking = brace and velocity < 0.0 and has_stamina
		braced_stance = brace and angle > 0.0 and has_stamina
	momentum = 1.1 if sweet else 1.0
	control_multiplier = 0.9 if velocity > 1.5 else 1.0
	# Retreating footing limits push transmission; Space remains the full brake.
	control_multiplier *= lerpf(1.0, ROLLBACK_PUSH_MIN_MULTIPLIER, clampf(-velocity / ROLLBACK_PUSH_FULL_SPEED, 0.0, 1.0))
	push_force = BASE_PUSH * push_multiplier * stamina_multiplier() * grip * (1.65 if exert else 1.0) * momentum * control_multiplier if pushing else 0.0
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
		action = "exert" if exert else "push"
	else:
		var recovery: float = 10.0 if safe else (7.0 if absf(velocity) < 0.01 else (3.0 if degrees <= 10.0 else 0.0))
		if safe and absf(velocity) > 0.05:
			recovery *= float(experiment.get("moving_shelf_recovery_scale", 1.0))
		elif not safe and distance >= float(experiment.get("uphill_recovery_after_m", 1000.0)):
			recovery *= float(experiment.get("uphill_recovery_scale", 1.0))
		# Releasing effort is required to recover; holding an exhausted input is not rest.
		if not effort_requested:
			stamina += recovery * recovery_multiplier * dt
		action = "slip" if slipping else "rest"
	stamina = clampf(stamina, 0.0, max_stamina)
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

