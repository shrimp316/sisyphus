extends "res://tests/balance/adjustment_v03/verify_recovery_bound.gd"

func paced_probe(ranks: Array,cadence: float,threshold: float,budget: float,length: float) -> Dictionary:
	var config: Dictionary = candidate(budget,1.0,length)
	config.gates[0].recovery_max_velocity = 0.9
	var stone: BoulderController = factory.create(world_for_gate(length),config)
	stone.apply_progression({"strength":ranks[0],"endurance":ranks[1],"recovery":ranks[2]})
	stone.stamina=stone.max_stamina
	stone.distance=750.0
	stone.peak=750.0
	stone.velocity=1.8
	var initial: Dictionary = stone.snapshot()
	var command: Array = [true,false,false]
	var period: int = maxi(1,roundi(cadence/DT))
	for step: int in range(120*500):
		if step%period==0:
			var rest: bool = stone.velocity>1.15 or (stone.stamina<stone.max_stamina*threshold and stone.velocity>0.6)
			command=[not rest,not rest and stone.velocity<0.65,false]
		stone._step_v02(DT,command[0],command[1],command[2])
		if stone.distance>=750.0+length or stone.distance<750.0 or stone.state!="climbing": break
	return {"ranks":ranks,"candidate":config,"cadence_seconds":period*DT,"stamina_rest_threshold":threshold,"passed":stone.distance>=750.0+length,"peak_gain":stone.peak-750.0,"seconds":stone.elapsed,"initial_state":initial,"final_state":stone.snapshot(),"policy":"Finite held-cadence threshold witness. Release iff v>1.15 or (S<threshold*C and v>.6); otherwise push, exert iff v<.65. No force prediction/quota observation. Environment restricts recovery abs(v)<=.9. Initial fixture only; not calibrated regular/skilled."}

func run() -> void:
	if not factory.build():
		quit(1)
		return
	var rows: Array = []
	for settings: Array in [[80.0,190.0],[40.0,150.0]]:
		for ranks: Array in [[8,8,8],[10,7,7],[7,10,7],[7,7,10]]:
			for cadence: float in [0.25,0.12]:
				for threshold: float in [0.4,0.5,0.6]:
					var row: Dictionary = paced_probe(ranks,cadence,threshold,settings[0],settings[1])
					rows.append(row)
					print("PACED length",settings[1]," ",ranks," ",cadence," ",threshold," pass",row.passed," gain",row.peak_gain)
	var output := FileAccess.open("res://tests/balance/results/act1-adjustment-v03/paced-search.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"source_sha256":Factory.SOURCE_SHA256,"trials":rows,"scope":"Constructive fixture search only. Failed rows are not physical impossibility proofs."},"\t"))
	output.close()
	quit(0)
