class_name ClimbBoulder
extends MasteryBoulder

# MVP environment coefficients only. Mastery still owns every purchased effect;
# this controller adds no run state or save fields and never changes force,
# integration, Slip duration, the retreat impulse, or the Runaway boundary.
const DIFFICULTY_PATH: String = "res://data/mastery/difficulty.json"
var difficulty: Dictionary = {}

func _init(terrain: MountainManager = null) -> void:
	super(terrain)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIFFICULTY_PATH))
	configure_difficulty(parsed if parsed is Dictionary else {"enabled":false})

func configure_difficulty(profile: Dictionary) -> void:
	# Replacement, not accumulation. An explicit disabled profile is exactly the
	# original MasteryBoulder. Missing scalar keys are neutral for probe profiles.
	difficulty = profile.duplicate(true)

func _active() -> bool:
	return bool(difficulty.get("enabled", false))

func _coefficient(values: Dictionary, key: String, fallback: float = 1.0) -> float:
	var value: Variant = values.get(key, fallback)
	if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0:
		return fallback
	return float(value)

func _surface_coefficient(key: String) -> float:
	var table: Variant = difficulty.get("surfaces", {})
	if not table is Dictionary: return 1.0
	var values: Variant = table.get(str(mountain.surface_at(distance).id), {})
	return _coefficient(values, key) if values is Dictionary else 1.0

func _training_coefficient(key: String) -> float:
	return _coefficient(difficulty, key) if distance < _coefficient(difficulty, "training_end_m", 0.0) else 1.0

func environment_info() -> Dictionary:
	var material: Dictionary = mountain.surface_at(distance)
	var environment: float = _surface_coefficient("drain") * _training_coefficient("training_drain_scale") if _active() else 1.0
	var surfaces: Dictionary = difficulty.get("surfaces", {}) if difficulty.get("surfaces", {}) is Dictionary else {}
	var surface: Dictionary = surfaces.get(str(material.id), {}) if surfaces.get(str(material.id), {}) is Dictionary else {}
	return {"enabled":_active(), "surface_label":str(material.label),
		"normal_drain_multiplier":environment * _coefficient(difficulty, "normal_drain_scale") if _active() else 1.0,
		"exert_drain_multiplier":environment * _coefficient(difficulty, "exert_drain_scale") if _active() else 1.0,
		"note":str(surface.get("note", "")) if _active() else "",
		"multiplier_scope":"environment_before_mastery"}

func _slip_gain_rate(rate: float, exert: bool, pushing: bool) -> float:
	if not _active(): return super._slip_gain_rate(rate, exert, pushing)
	if not pushing or mountain.is_shelf(distance) or mountain.angle_at(distance) <= 0.0: return 0.0
	return super._slip_gain_rate(rate, exert, pushing) * _coefficient(difficulty, "slip_gain_scale") * _surface_coefficient("slip") * _training_coefficient("training_slip_scale")

func _slip_decay_rate(rate: float, exert: bool, pushing: bool) -> float:
	if _active() and pushing and not exert and not mountain.is_shelf(distance) and mountain.angle_at(distance) > 0.0:
		rate *= _coefficient(difficulty, "normal_push_decay_scale")
	return super._slip_decay_rate(rate, exert, pushing)

func _stamina_drain_rate(rate: float, exert: bool, sweet: bool, bracing: bool) -> float:
	if _active():
		rate *= _coefficient(difficulty, "brace_drain_scale" if bracing else ("exert_drain_scale" if exert else "normal_drain_scale"))
		rate *= _surface_coefficient("drain")
		if not bracing: rate *= _training_coefficient("training_drain_scale")
	return super._stamina_drain_rate(rate, exert, sweet, bracing)

func _stamina_recovery_rate(rate: float, degrees: float, safe: bool) -> float:
	if _active():
		rate *= _coefficient(difficulty, "shelter_recovery_scale" if safe else ("uphill_recovery_scale" if absf(velocity) < 0.01 else "moving_recovery_scale"))
		if not safe: rate *= _surface_coefficient("recovery")
	# Apply BRE floors and additive stationary/generic bonuses after environment
	# scaling; the base integrator applies recovery_multiplier exactly once.
	return super._stamina_recovery_rate(rate, degrees, safe)
