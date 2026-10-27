class_name MasteryEffects
extends RefCounted

# Purchased/enabled node data is the sole source. Rebuilding this value object
# never compounds a previously applied multiplier.
var values: Dictionary = {}

func configure(modifiers: Dictionary) -> void:
	values.clear()
	for key: Variant in modifiers.get("effects", {}):
		var value: Variant = modifiers.effects[key]
		if (value is float or value is int) and is_finite(float(value)) and float(value) >= 0.0:
			values[str(key)] = float(value)

func amount(key: String, fallback: float = 0.0) -> float:
	return float(values.get(key, fallback))

func drain_factor(exert: bool, sweet: bool, bracing: bool, retreating: bool, low: bool, departure: bool) -> float:
	var reduction: float = amount("low_stamina_drain_reduction") if low else 0.0
	if bracing:
		reduction += amount("brace_drain_reduction")
		if retreating: reduction += amount("retreat_brace_drain_reduction")
	else:
		reduction += amount("exert_drain_reduction") if exert else amount("normal_drain_reduction")
		if sweet and not exert: reduction += amount("sweet_normal_drain_reduction")
		if departure: reduction += amount("special_departure_drain_reduction")
	return maxf(0.05, 1.0 - reduction)

func recovery_rate(base: float, degrees: float, speed: float) -> float:
	# These nodes fill formerly nonrecovering slope/speed bands; they never
	# replace the stronger original stationary recovery with a lower rate.
	if degrees >= 10.0 and degrees <= 15.0 and speed > 0.0:
		base = maxf(base, amount("gentle_coast_recovery"))
	if degrees > 15.0 and absf(speed) <= 0.05:
		base = maxf(base, amount("steep_stationary_recovery"))
	var generic: float = 1.0 + amount("recovery_bonus")
	var stationary: float = amount("stationary_recovery_bonus") if absf(speed) < 0.01 else 0.0
	return base * (generic + stationary) / generic
