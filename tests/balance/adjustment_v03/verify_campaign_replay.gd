extends "res://tests/balance/adjustment_v03/replay.gd"

var purchase_observations: Array=[]

func purchase(job: Dictionary,profile: Dictionary,boulder: BoulderController) -> void:
	var prior: int=profile.purchases.size()
	var condition: Dictionary={"job_id":job.id,"seed":boulder.mountain.seed_value,"seconds":float(profile.time)+boulder.elapsed,"distance_m":boulder.distance,"velocity":boulder.velocity,"state":boulder.state,"on_shelf":boulder.mountain.is_shelf(boulder.distance)}
	super.purchase(job,profile,boulder)
	if profile.purchases.size()>prior:
		condition.purchases=profile.purchases.slice(prior)
		condition.guard_passed=condition.state=="climbing" and bool(condition.on_shelf) and absf(float(condition.velocity))<=0.05
		purchase_observations.append(condition)

func run() -> void:
	super.run()
	var failures: int=purchase_observations.filter(func(row):return not row.guard_passed).size()
	var output:=FileAccess.open("res://tests/balance/results/act1-adjustment-v03/independent-campaign-purchase-replay.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"purchase_events":purchase_observations.size(),"failures":failures,"observations":purchase_observations,"scope":"Actual raw-input replays of first, second and terminal attempts in all20campaigns. Conditions observed immediately before each existing purchase() call; other attempts are covered by JSON continuity/geometry/XP audit."},"\t"))
	output.close()
	print("V03 PURCHASE REPLAY ",purchase_observations.size()," events, ",failures," failures")
	if failures>0:quit(1)
