extends RefCounted

const SOURCE_PATH: String = "res://scripts/boulder_controller.gd"
const SOURCE_SHA256: String = "30a312b144383be64fc6fe35b8ad107ebba9a90672d9dda941f9ef8018279944"
const GENERATED_PATH: String = "res://tests/balance/results/act1-adjustment-v02/generated_controller.gd"
var generated: GDScript
var patch_manifest: Dictionary = {}

func build() -> bool:
	if generated != null:
		return true
	if FileAccess.get_sha256(SOURCE_PATH) != SOURCE_SHA256:
		push_error("Production controller changed; v02 scalar instrumentation refuses an unaudited source")
		return false
	var source: String = FileAccess.get_file_as_string(SOURCE_PATH)
	var start: int = source.find("func _step_v02(")
	var finish: int = source.find("\nfunc _enter_runaway", start)
	if start < 0 or finish < 0:
		return false
	var body: String = source.substr(start, finish - start)
	var gain_anchor: String = "\tvar slip_recovery: float = 20.0 if safe else (10.0 if absf(velocity) < 0.01 else (4.0 if not (exert and pushing) else 0.0))"
	var apply_anchor: String = "\tslip = clampf(slip + (slip_gain - slip_recovery) * dt, 0.0, 100.0)"
	var recovery_anchor: String = "\t\tvar recovery: float = 10.0 if safe else (7.0 if absf(velocity) < 0.01 else (3.0 if degrees <= 10.0 else 0.0))"
	for anchor: String in [gain_anchor, apply_anchor, recovery_anchor]:
		if body.count(anchor) != 1:
			push_error("Scalar instrumentation anchor is absent or ambiguous")
			return false
	body = body.replace(gain_anchor, "\tif distance >= 500.0:\n\t\tslip_gain *= float(experiment.get(\"slip_gain_after500_scale\", 1.0))\n" + gain_anchor)
	body = body.replace(apply_anchor, "\tif not safe and distance >= 750.0:\n\t\tslip_recovery *= float(experiment.get(\"slip_decay_after750_scale\", 1.0))\n" + apply_anchor)
	body = body.replace(recovery_anchor, recovery_anchor + "\n\t\tif safe and absf(velocity) > 0.05:\n\t\t\trecovery *= float(experiment.get(\"moving_shelf_recovery_scale\", 1.0))\n\t\telif not safe and distance >= float(experiment.get(\"uphill_recovery_after_m\", 1000.0)):\n\t\t\trecovery *= float(experiment.get(\"uphill_recovery_scale\", 1.0))")
	var generated_source: String = "extends \"res://tests/balance/adjustment_v02/observed_controller.gd\"\n\n# GENERATED from production SHA256 " + SOURCE_SHA256 + ".\n# Only three scalar sites are instrumented; do not edit this artifact.\n" + body + "\n"
	generated = GDScript.new()
	generated.source_code = generated_source
	if generated.reload() != OK or not generated.can_instantiate():
		generated = null
		return false
	patch_manifest = {"type": "instrumentation", "source": SOURCE_PATH, "source_sha256": SOURCE_SHA256, "generated_sha256": generated_source.sha256_text(), "generated_artifact": GENERATED_PATH, "anchors": {"slip_gain": gain_anchor, "slip_decay": apply_anchor, "released_input_recovery": recovery_anchor}, "changes": ["Slip gain multiplier at distance >=500", "Non-shelf Slip decay multiplier at distance >=750", "Moving shelf recovery scalar; separately labeled diagnostic uphill recovery scalar"], "preserved": ["fixed DT", "slip threshold", "slip duration", "runaway threshold", "ledge force calculation", "all integration and state transitions"]}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GENERATED_PATH.get_base_dir()))
	if not FileAccess.file_exists(GENERATED_PATH) or FileAccess.get_file_as_string(GENERATED_PATH) != generated_source:
		var artifact := FileAccess.open(GENERATED_PATH, FileAccess.WRITE)
		if artifact == null:
			return false
		artifact.store_string(generated_source)
		artifact.close()
	return true

func create(world: MountainManager, candidate: Dictionary) -> BoulderController:
	if not build():
		return null
	var controller: BoulderController = generated.new(world)
	controller.experiment = candidate.duplicate(true)
	return controller
