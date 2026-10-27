extends "res://scripts/boulder_controller.gd"

# Test-only sensitivity hook. All integration, collision, slip, and state logic
# remain inherited from the production controller.
var drain_scale: float = 1.0

func slope_drain_multiplier(angle_degrees: float) -> float:
	return super.slope_drain_multiplier(angle_degrees) * drain_scale
