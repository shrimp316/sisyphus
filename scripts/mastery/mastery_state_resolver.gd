extends RefCounted
## Eligibility, prerequisites and selection are intentionally independent.
const KIND := {"strength": "strength", "endurance": "endurance", "breath": "recovery"}

static func resolve(node: Dictionary, snapshot: Dictionary, selected_id: String = "") -> Dictionary:
	var special: bool = node.track == "special"
	var rank: int = 0 if special else int(snapshot.ranks.get(KIND[node.track], 0))
	var purchased: bool = not special and rank >= int(node.index)
	var eligible: bool
	if special:
		eligible = int(snapshot.first_summit_run_number) >= 0 and int(snapshot.current_run_number) > int(snapshot.first_summit_run_number)
	else:
		eligible = bool(snapshot.first_reach_flags.get(str(node.milestone_m), false))
	var prerequisite: bool = special or rank >= int(node.index) - 1
	var permission: bool = not special and int(snapshot.pending_points) > 0
	var base_state := "PURCHASED"
	if not purchased:
		if not eligible: base_state = "STORY_LOCKED"
		elif not prerequisite: base_state = "LOCKED"
		elif not permission: base_state = "INSUFFICIENT_EXP"
		else: base_state = "AVAILABLE"
	return {"base_state": base_state, "eligible": eligible, "prerequisite": prerequisite,
		"purchased": purchased, "selected": str(node.node_id) == selected_id,
		"can_purchase": base_state == "AVAILABLE"}
