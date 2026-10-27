extends SceneTree

const Factory = preload("res://tests/balance/adjustment_v03/controller_factory.gd")
const Terrain = preload("res://tests/balance/adjustment_v03/terrain.gd")
const DT: float = 1.0/120.0
var factory=Factory.new()
var checks: Array=[]

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks.append({"passed":value,"name":label})
	print("PASS " if value else "FAIL ",label)

func same(a: Variant,b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key: Variant in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i: int in a.size():
			if not same(a[i],b[i]):return false
		return true
	if (a is float or a is int) and (b is float or b is int):return absf(float(a)-float(b))<0.0000001
	return a==b

func run() -> void:
	if not factory.build():quit(2);return
	var reconstructed: String=factory.generated.source_code
	reconstructed=reconstructed.substr(reconstructed.find("func _step_v02("))
	reconstructed=reconstructed.trim_suffix("\n\t_gate_after_step()\n")
	var patches: Array=factory.patch_manifest.patches.duplicate(true)
	patches.reverse()
	for patch: Array in patches:
		reconstructed=reconstructed.replace(str(patch[1]),str(patch[0]))
	check(reconstructed.sha256_text()==str(factory.patch_manifest.original_function_sha256),"inverse scalar patches exactly recover original function bytes")
	for weather: String in ["clear","rain"]:
		var world=Terrain.new(202,false,6,weather)
		world.configure_experiment({})
		for speed: float in [-.1,.0005,.8,1.6]:
			for amount: float in [.001,20,50,100]:
				var production=BoulderController.new(world)
				var generated=factory.create(world,{})
				for stone: BoulderController in [production,generated]:
					stone.distance=800
					stone.peak=800
					stone.velocity=speed
					stone.stamina=amount
				for step: int in range(120):
					for stone: BoulderController in [production,generated]:stone._step_v02(DT,step%30<20,step%40<10,step%55>50)
				var snapshot: Dictionary=generated.snapshot()
				snapshot.erase("gate_ledger")
				snapshot.erase("active_gate_id")
				check(same(production.snapshot(),snapshot),"neutral physical parity %s v%s S%s"%[weather,speed,amount])
	var config: Dictionary={"gates":[{"id":"g","start_m":750,"end_m":940,"angle_degrees":45,"surface":"STONE","recovery_seconds_budget":DT/3,"recovery_rate":7,"recovery_min_stamina":1}],"connection_layout":[{"start_m":940,"end_m":950,"shelf":true}]}
	var world=Terrain.new(101,false,6,"rain")
	world.configure_experiment(config)
	var stone=factory.create(world,config)
	stone.apply_progression({"recovery":10})
	stone.distance=800
	stone.stamina=50
	stone._step_v02(DT,false,false,false)
	check(absf(stone.stamina-(50+7*1.2*DT/3))<1e-10,"fractional final opportunity consumes only remaining time with existing recovery multiplier")
	check(absf(float(stone.gate_ledger.g.seconds_used)-DT/3)<1e-10 and stone.gate_ledger.g.seconds_remaining==0,"partial quota accounting exact")
	var saved: Dictionary=stone.snapshot()
	var clone=factory.create(world,config)
	clone.apply_progression({"recovery":10})
	clone.restore(saved)
	for s: BoulderController in [stone,clone]:s._step_v02(DT,false,false,false)
	check(same(stone.snapshot(),clone.snapshot()),"snapshot restoration preserves exhausted quota")
	check(absf(stone.stamina-(50+7*1.2*DT/3))<1e-10,"exhausted quota permits no extra released recovery")
	stone.distance=749
	stone._step_v02(DT,true,false,false)
	stone.distance=750
	var before: float=stone.stamina
	stone._step_v02(DT,false,false,false)
	check(stone.gate_ledger.g.entries==2 and stone.gate_ledger.g.seconds_remaining==0 and stone.stamina==before,"leave/reenter does not refund quota or permit refill")
	config.gates[0].recovery_seconds_budget=2.0
	var states: Array=[]
	for fps: int in [30,144]:
		var s=factory.create(world,config)
		s.distance=800
		s.peak=800
		s.stamina=45
		s.velocity=.8
		for frame: int in range(fps*2):
			var phase: int=frame/(fps/2)
			var command: Array=[[false,false,false],[true,false,false],[false,false,true],[true,true,false]][phase]
			s.advance(1.0/fps,command[0],command[1],command[2])
		states.append(s.snapshot())
	check(same(states[0],states[1]),"30/144FPS held schedule agrees including finite recovery ledger")
	var failures: int=checks.filter(func(row):return not row.passed).size()
	var output:=FileAccess.open("res://tests/balance/results/act1-adjustment-v03/independent-runtime-verification.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks.size(),"failures":failures,"results":checks,"factory_manifest":factory.patch_manifest},"\t"))
	output.close()
	print("V03 INDEPENDENT ",checks.size()," checks, ",failures," failures")
	quit(1 if failures else 0)
