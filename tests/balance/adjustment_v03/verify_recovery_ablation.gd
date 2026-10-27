extends "res://tests/balance/adjustment_v03/verify_recovery_bound.gd"

func run() -> void:
	if not factory.build():
		quit(1)
		return
	var rows: Array = []
	for recovery: int in [0,7,10]:
		for cadence: float in [0.25,0.12]:
			var row: Dictionary = probe([7,7,recovery],cadence,0.5,1.0,140.0,255.0)
			rows.append(row)
			print("ABLATION recovery",recovery," cadence",cadence," pass",row.passed," peak",row.peak_gain)
	for ranks: Array in [[0,0,0],[7,7,10]]:
		var row: Dictionary = probe(ranks,0.25,0.5,0.0,140.0,255.0)
		row.certificate_status="not_covered: zero stamina refill permitted"
		rows.append(row)
		print("MIN0 ",ranks," pass",row.passed," peak",row.peak_gain)
	var output := FileAccess.open("res://tests/balance/results/act1-adjustment-v03/recovery-ablation.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"source_sha256":Factory.SOURCE_SHA256,"candidate":candidate(140.0,1.0,255.0),"trials":rows,"interpretation":"Matched strength/endurance, policy and gate; only existing recovery rate rank differs. Initial entry fixture; not full-route/policy population evidence. min_stamina0 variants explicitly outside certificate."},"\t"))
	output.close()
	quit(0)
