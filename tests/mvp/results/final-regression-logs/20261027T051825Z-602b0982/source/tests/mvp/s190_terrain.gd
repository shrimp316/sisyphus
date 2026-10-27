extends "res://tests/balance/adjustment_v03/terrain.gd"

# S190's material Slip scalar remains test-only; no production terrain changes.
func slip_multiplier_at(position: float) -> float:
	return super.slip_multiplier_at(position) * (0.6 if position >= 750.0 and position < 940.0 else 1.0)
