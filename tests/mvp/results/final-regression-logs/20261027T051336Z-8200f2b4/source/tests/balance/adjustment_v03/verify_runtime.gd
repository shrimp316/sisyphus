extends "res://tests/balance/adjustment_v03/simulator.gd"

var checks: Array=[]
func check(ok: bool,label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: printerr("FAILED: ",label)

func run() -> void:
	if not factory.build():
		quit(2)
		return
	var old_script: GDScript=load("res://tests/balance/results/act1-adjustment-v02/generated_controller.gd")
	var old_terrain=load("res://tests/balance/adjustment_v02/terrain.gd")
	for scenario: String in ["baseline","G123"]:
		var old_candidate: Dictionary={}
		var new_candidate: Dictionary={}
		if scenario=="G123":
			old_candidate={"geometry_overrides":[{"chunk_index":15,"climb_length":50,"angle":45,"surface":"STONE","wet_ranges":[]},{"chunk_index":16,"climb_length":50,"angle":45,"surface":"STONE","wet_ranges":[]},{"chunk_index":17,"climb_length":23,"angle":45,"surface":"STONE","wet_ranges":[]}],"uphill_recovery_after_m":750,"uphill_recovery_scale":0}
			new_candidate={"gates":[{"id":"g3","start_m":750,"end_m":873,"angle_degrees":45,"surface":"STONE"}],"connection_layout":[{"start_m":873,"end_m":900,"shelf":true,"surface":"STONE"}],"uphill_recovery_after_m":750,"uphill_recovery_scale":0}
		var a_world=old_terrain.new(101,false,6,"rain")
		a_world.configure_experiment(old_candidate)
		var b_world:=create_world(101,{"weather":"rain"})
		configure_world(b_world,new_candidate)
		for meter: int in range(250):
			check(a_world.segment_at(meter)==b_world.segment_at(meter),scenario+" unchanged early "+str(meter))
		for start_m: float in [0.0,750.0,873.0]:
			var a=old_script.new(a_world)
			a.experiment=old_candidate
			var b=factory.create(b_world,new_candidate)
			for stone: BoulderController in [a,b]:
				stone.distance=start_m
				stone.peak=start_m
				stone.velocity=0.8
			for step: int in range(600):
				var push: bool=step%40<30
				var exert: bool=step%100<10
				a._step_v02(DT,push,exert,false)
				b._step_v02(DT,push,exert,false)
			var matches: bool=true
			var snapshot_a: Dictionary=a.snapshot()
			var snapshot_b: Dictionary=b.snapshot()
			for key: String in snapshot_a:
				if snapshot_a[key] is float: matches=matches and absf(float(snapshot_a[key])-float(snapshot_b[key]))<0.0000001
				else: matches=matches and snapshot_a[key]==snapshot_b[key]
			check(matches,scenario+" physics parity "+str(start_m))
	var candidate: Dictionary={"gates":[{"id":"g","start_m":750,"end_m":940,"angle_degrees":45,"recovery_rate":7,"recovery_seconds_budget":2,"recovery_min_stamina":1}],"connection_layout":[{"start_m":940,"end_m":950,"shelf":true}]}
	var world:=create_world(101,{})
	configure_world(world,candidate)
	var stone=factory.create(world,candidate)
	stone.distance=800
	stone.peak=800
	stone.stamina=50
	stone._step_v02(DT,false,false,false)
	check(absf(stone.stamina-(50+7*DT))<0.0000001,"released recovery exact rate")
	check(absf(float(stone.gate_ledger.g.seconds_remaining)-(2-DT))<0.0000001,"time quota exact decrement")
	var saved: Dictionary=stone.snapshot()
	var clone=factory.create(world,candidate)
	clone.restore(saved)
	for controller: BoulderController in [stone,clone]: controller._step_v02(DT,false,false,false)
	check(stone.snapshot()==clone.snapshot(),"snapshot restores quota and entry history")
	stone.stamina=0
	var remaining: float=stone.gate_ledger.g.seconds_remaining
	stone._step_v02(DT,false,false,false)
	check(stone.stamina==0 and stone.gate_ledger.g.seconds_remaining==remaining,"minimum stamina forbids zero refill")
	stone.stamina=stone.max_stamina
	stone.velocity=0
	stone._step_v02(DT,false,false,false)
	check(stone.stamina==stone.max_stamina and float(stone.gate_ledger.g.seconds_remaining)<remaining,"full-cap opportunity time still consumed")
	remaining=stone.gate_ledger.g.seconds_remaining
	stone._step_v02(DT,true,false,false)
	check(stone.gate_ledger.g.seconds_remaining==remaining,"pushing cannot recharge")
	stone._step_v02(DT,false,false,true)
	check(stone.gate_ledger.g.seconds_remaining==remaining,"bracing cannot recharge")
	stone.distance=749.0
	stone._step_v02(DT,false,false,false)
	stone.distance=750.0
	stone._step_v02(DT,true,false,false)
	check(stone.gate_ledger.g.seconds_remaining==remaining and stone.gate_ledger.g.entries==2,"retreat and reentry never refund quota")
	var failures: int=checks.filter(func(item: Dictionary)->bool:return not item.passed).size()
	var file:=FileAccess.open("res://tests/balance/results/act1-adjustment-v03/runtime-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks.size(),"failures":failures,"results":checks},"\t"))
	print("V03 RUNTIME ",checks.size()," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
