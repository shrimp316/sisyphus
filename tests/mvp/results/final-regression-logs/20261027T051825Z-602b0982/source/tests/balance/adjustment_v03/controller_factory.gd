extends RefCounted

const SOURCE_PATH: String = "res://scripts/boulder_controller.gd"
const SOURCE_SHA256: String = "30a312b144383be64fc6fe35b8ad107ebba9a90672d9dda941f9ef8018279944"
const GENERATED_PATH: String = "res://tests/balance/results/act1-adjustment-v03/generated_controller.gd"
var generated: GDScript
var patch_manifest: Dictionary = {}

func build() -> bool:
	if generated != null: return true
	if FileAccess.get_sha256(SOURCE_PATH) != SOURCE_SHA256:
		push_error("v03 refuses unaudited production source")
		return false
	var source: String = FileAccess.get_file_as_string(SOURCE_PATH)
	var start: int = source.find("func _step_v02(")
	var finish: int = source.find("\nfunc _enter_runaway",start)
	if start < 0 or finish < 0: return false
	var body: String = source.substr(start,finish-start)
	var original_function_hash: String = body.sha256_text()
	var patches: Array = [
		["\tvar old_distance: float = distance", "\t_gate_before_step(dt,push,exert,brace)\n\tvar old_distance: float = distance"],
		["\tvar slip_recovery: float = 20.0 if safe else (10.0 if absf(velocity) < 0.01 else (4.0 if not (exert and pushing) else 0.0))", "\tslip_gain *= gate_scale(\"slip_gain_scale\")\n\tif distance >= 500.0: slip_gain *= float(experiment.get(\"slip_gain_after500_scale\",1.0))\n\tvar slip_recovery: float = 20.0 if safe else (10.0 if absf(velocity) < 0.01 else (4.0 if not (exert and pushing) else 0.0))"],
		["\tslip = clampf(slip + (slip_gain - slip_recovery) * dt, 0.0, 100.0)", "\tslip_recovery *= gate_scale(\"slip_decay_scale\")\n\tif not safe and distance >= 750.0: slip_recovery *= float(experiment.get(\"slip_decay_after750_scale\",1.0))\n\tslip = clampf(slip + (slip_gain - slip_recovery) * dt, 0.0, 100.0)"],
		["\tvar drain_multiplier: float = slope_drain_multiplier(degrees)", "\tvar drain_multiplier: float = slope_drain_multiplier(degrees) * gate_scale(\"drain_scale\")"],
		["\t\tvar recovery: float = 10.0 if safe else (7.0 if absf(velocity) < 0.01 else (3.0 if degrees <= 10.0 else 0.0))", "\t\tvar recovery: float = 10.0 if safe else (7.0 if absf(velocity) < 0.01 else (3.0 if degrees <= 10.0 else 0.0))\n\t\tif safe and absf(velocity)>0.05: recovery *= float(experiment.get(\"moving_shelf_recovery_scale\",1.0))\n\t\telif not safe and distance >= float(experiment.get(\"uphill_recovery_after_m\",1000.0)): recovery *= float(experiment.get(\"uphill_recovery_scale\",1.0))"],
		["\t\t\tstamina += recovery * recovery_multiplier * dt", "\t\t\tstamina += _gate_recovery_amount(recovery,dt,effort_requested,safe)"]
	]
	for patch: Array in patches:
		if body.count(str(patch[0])) != 1:
			push_error("v03 ambiguous instrumentation anchor")
			return false
		body = body.replace(str(patch[0]),str(patch[1]))
	body += "\n\t_gate_after_step()\n"
	var generated_source: String = "extends \"res://tests/balance/adjustment_v03/controller.gd\"\n# Generated from audited production, no copied alternative integrator.\n"+body
	generated = GDScript.new()
	generated.source_code = generated_source
	if generated.reload()!=OK or not generated.can_instantiate():
		generated=null
		return false
	patch_manifest={"type":"instrumentation","source":SOURCE_PATH,"source_sha256":SOURCE_SHA256,"original_function_sha256":original_function_hash,"generated_sha256":generated_source.sha256_text(),"generated_artifact":GENERATED_PATH,"patches":patches,"appended":"_gate_after_step() telemetry","recovery_semantics":"Test-only finite environmental released-recovery time. Rank-independent seconds quota; eligible time consumed even at stamina cap. Amount=rate*existing recovery_multiplier*eligible_dt clamped by actual missing stamina. No refund on retreat/reentry/stall; fresh run resets quota.","preserved":["integration","state transitions","force","ledge thresholds","slip threshold/duration","existing rank effects"]}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GENERATED_PATH.get_base_dir()))
	if not FileAccess.file_exists(GENERATED_PATH) or FileAccess.get_file_as_string(GENERATED_PATH)!=generated_source:
		var file:=FileAccess.open(GENERATED_PATH,FileAccess.WRITE)
		file.store_string(generated_source)
	return true

func create(world: MountainManager,candidate: Dictionary) -> BoulderController:
	if not build(): return null
	var controller: BoulderController = generated.new(world)
	controller.experiment=candidate.duplicate(true)
	return controller
