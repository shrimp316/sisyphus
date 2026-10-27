extends RefCounted
## Read-only presentation adapter for the EXISTING MVP wallet and node definitions.
## Purchases remain exclusively in the host's confirmation/safe-purchase path.
signal changed
signal purchase_succeeded(node_id: String)
const PREFIX := {"strength": "STR", "endurance": "END", "breath": "BRE", "special": "SPC"}
var profile: RefCounted
var purchase_allowed := false
var run_number := 1

static func model_id(row: Dictionary) -> String:
	return "%s%02d" % [PREFIX[row.track], int(row.index)]

static func view_id(id: String) -> String:
	for track: String in PREFIX:
		if id.begins_with(PREFIX[track]):
			return "act1_%s_%02d" % [track, int(id.right(2))]
	return ""

func bind(value: RefCounted, allowed: bool, current_run: int) -> void:
	profile = value
	purchase_allowed = allowed
	run_number = current_run

func snapshot() -> Dictionary:
	return {"fixture_id": "live_mvp", "mock": false, "current_run_number": run_number,
		"available_exp": 0 if profile == null else profile.available_exp}

func resolve(row: Dictionary, selected_id: String) -> Dictionary:
	var id := model_id(row)
	var special: bool = row.track == "special"
	var purchased: bool = profile != null and id in profile.purchased_mastery_nodes
	var eligible: bool = profile != null and id in profile.permanent_mastery_unlocks
	if special: eligible = eligible and profile.first_summit_completed
	var state := "locked" if profile == null else str(profile.get_node_state(id))
	var prerequisite: bool = state != "prerequisite"
	var base_state := "STORY_LOCKED"
	if purchased: base_state = "PURCHASED"
	elif not eligible: base_state = "STORY_LOCKED"
	elif not prerequisite: base_state = "LOCKED"
	elif special or state in ["disabled", "insufficient_exp"]: base_state = "INSUFFICIENT_EXP"
	elif state == "available": base_state = "AVAILABLE"
	var allowed: bool = not special and purchase_allowed and state == "available" and not purchased
	return {"base_state": base_state, "eligible": eligible, "prerequisite": prerequisite,
		"purchased": purchased, "selected": row.node_id == selected_id, "can_purchase": allowed,
		"model_id": id, "model_state": state}

func can_request_purchase(id: String) -> bool:
	return profile != null and not id.begins_with("SPC") and purchase_allowed and profile.can_purchase_node(id)
