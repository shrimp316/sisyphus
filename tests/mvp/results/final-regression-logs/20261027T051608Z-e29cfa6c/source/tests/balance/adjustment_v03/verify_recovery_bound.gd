extends SceneTree

const Factory = preload("res://tests/balance/adjustment_v03/controller_factory.gd")
const Terrain = preload("res://tests/balance/adjustment_v02/terrain.gd")
const DT: float = 1.0/120.0
const Q: float = 1.7
var factory = Factory.new()

func _initialize() -> void:
	call_deferred("run")

func candidate(budget: float = 80.0, minimum: float = 1.0, length: float = 190.0, angle: float = 45.0) -> Dictionary:
	var start: float = 650.0 if length>250.0 else 750.0
	return {"gates":[{"id":"proof_gate","start_m":start,"end_m":start+length,"angle_degrees":angle,"surface":"STONE","drain_scale":1.0,"slip_gain_scale":0.6,"recovery_seconds_budget":budget/7.0,"recovery_rate":7.0,"recovery_min_stamina":minimum}]}

func world_for_gate(length: float = 190.0, angle: float = 45.0):
	var world = Terrain.new(101,false,6,"clear")
	var overrides: Array = []
	var start: float = 650.0 if length>250.0 else 750.0
	for index: int in range(int(start/50.0),20):
		overrides.append({"chunk_index":index,"angle":angle,"surface":"STONE","climb_length":clampf(start+length-index*50.0,0.0,50.0),"wet_ranges":[]})
	world.configure_experiment({"geometry_overrides":overrides})
	return world

func certificate(strength: int,endurance: int,recovery: int,budget: float,length: float = 190.0, angle: float = 45.0) -> Dictionary:
	var c: float = 3.0*sin(deg_to_rad(angle))+0.2
	var q: float = BoulderController.new().slope_drain_multiplier(angle)
	var p: float = 1.0+0.02*strength
	var cap: float = 100.0*(1.0+0.02*endurance)
	var ratios: Array = []
	var low_ratios: Array = []
	for exert: bool in [false,true]:
		for band: Dictionary in [{"v":0.45,"momentum":1.0,"control":1.0,"drain":1.0},{"v":1.2,"momentum":1.1,"control":1.0,"drain":0.8},{"v":1.5,"momentum":1.0,"control":1.0,"drain":1.0},{"v":1.8,"momentum":1.0,"control":0.9,"drain":1.0}]:
			var force: float = 2.6*p*float(band.momentum)*float(band.control)*(1.65 if exert else 1.0)
			var drain: float = q*float(band.drain)*(3.0 if exert else 1.0)
			ratios.append(force*minf(1.8,float(band.v)+force*DT)/drain)
		var force: float = 2.6*p*(1.65 if exert else 1.0)
		var drain: float = q*(3.0 if exert else 1.0)
		# Includes negative-to-positive and the |v|<=.001 stiction branch.
		var next_speed: float = 0.001+force*DT
		low_ratios.append((c*next_speed*DT+0.5*next_speed*next_speed)/(0.65*drain*DT))
	var ratio: float = maxf(ratios.max(),low_ratios.max())
	var qmax: float = 3.0*q*DT
	var recovered: float = budget*(1.0+0.02*recovery)
	var resource: float = 0.885*cap+recovered+qmax
	var supplied: float = ratio*resource+1.62
	var required: float = c*(length-1.8*DT)
	return {"ranks":{"strength":strength,"endurance":endurance,"recovery":recovery},"gate_length":length,"angle":angle,"drain_multiplier":q,"retarding_coefficient":c,"forward_ratio":ratios.max(),"crosszero_and_stiction_ratio":low_ratios.max(),"ratio":ratio,"qmax":qmax,"recovery_upper":recovered,"weighted_resource_upper":resource,"supply_upper":supplied,"necessary_work_lower":required,"margin":supplied-required,"conditional_impossibility":supplied<required and angle>=39.0 and angle<=45.0,"requires":"Constant39..45degrees dry STONE, no internal ledge/support/shelf/purchase, fixed ranks, recovery_min_stamina>0, total actual recovery<=budget*existing recovery multiplier. min_stamina=0 invalidates this resource certificate."}

func step_grid(angle: float = 45.0) -> Dictionary:
	var config: Dictionary = candidate(80.0,1.0,190.0,angle)
	var world = world_for_gate(190.0,angle)
	var bound: Dictionary = certificate(0,0,0,80.0,190.0,angle)
	var q: float = float(bound.drain_multiplier)
	var count: int = 0
	var failures: Array = []
	var max_violation: float = 0.0
	for speed: float in [-3.999,-0.1,-0.001,-0.000001,0.0,0.000001,0.0005,0.001,0.001001,0.15,0.45,1.2,1.5,1.8]:
		for stamina: float in [0.0,0.000001,0.0424999,0.0425,0.05,0.999,1.0,19.999999,20.0,49.999999,50.0,100.0]:
			for slip: float in [0.0,99.999]:
				for remaining: float in [0.0,0.7]:
					for bits: int in range(8):
						var stone: BoulderController = factory.create(world,config)
						stone.distance=800.0
						stone.peak=800.0
						stone.velocity=speed
						stone.stamina=stamina
						stone.slip=slip
						stone.slip_remaining=remaining
						var rho: float = stone.stamina_multiplier()
						var initial: float = float(bound.retarding_coefficient)*stone.distance+0.5*pow(maxf(speed,0.0),2)
						stone._step_v02(DT,(bits&1)!=0,(bits&2)!=0,(bits&4)!=0)
						var after: float = float(bound.retarding_coefficient)*stone.distance+0.5*pow(maxf(stone.velocity,0.0),2)
						var nominal: float = q*(3.0 if stone.action=="exert" else 1.0)*(0.8 if speed>=0.45 and speed<=1.2 else 1.0)*DT if stone.action in ["push","exert"] else 0.0
						var violation: float = after-initial-float(bound.ratio)*rho*nominal
						max_violation=maxf(max_violation,violation)
						count+=1
						if violation>0.00000001:
							failures.append({"v":speed,"S":stamina,"bits":bits,"slip":slip,"remaining":remaining,"violation":violation})
	return {"angle":angle,"checks":count,"failures":failures,"maximum_violation":max_violation,"meaning":"Supporting actual generated-controller grid; not exhaustive proof."}

func probe(ranks: Array,cadence: float,threshold: float,minimum: float = 1.0,budget: float = 80.0,length: float = 190.0) -> Dictionary:
	var config: Dictionary = candidate(budget,minimum,length)
	var world = world_for_gate(length)
	var start: float = float(config.gates[0].start_m)
	var stone: BoulderController = factory.create(world,config)
	stone.apply_progression({"strength":ranks[0],"endurance":ranks[1],"recovery":ranks[2]})
	stone.stamina=stone.max_stamina
	stone.distance=start
	stone.peak=start
	stone.velocity=1.8
	var initial: Dictionary = stone.snapshot()
	var command: Array = [true,false,false]
	var period: int = maxi(1,roundi(cadence/DT))
	for step: int in range(120*500):
		if step%period==0:
			var rest: bool = stone.stamina<stone.max_stamina*threshold and stone.velocity>0.9
			command=[not rest,not rest and stone.velocity<1.0,false]
		stone._step_v02(DT,command[0],command[1],command[2])
		if stone.distance>=start+length or stone.distance<start or stone.state!="climbing": break
	return {"ranks":ranks,"cadence_seconds":period*DT,"stamina_rest_threshold":threshold,"recovery_min_stamina":minimum,"passed":stone.distance>=start+length,"peak_gain":stone.peak-start,"seconds":stone.elapsed,"initial_state":initial,"final_state":stone.snapshot(),"policy":"Synthetic held-cadence threshold fixture witness; release iff S<threshold*capacity and velocity>.9, otherwise push/exert iff velocity<1; not calibrated regular/skilled, no mutation after initial fixture."}

func run() -> void:
	if not factory.build():
		quit(1)
		return
	if "--angle-grid" in OS.get_cmdline_user_args():
		var grids: Array = [step_grid(39.0),step_grid(40.0),step_grid(45.0)]
		var angle_certs: Array = [certificate(0,0,0,0.0,114.0,39.0),certificate(0,0,0,10.0,127.0,39.0),certificate(0,0,0,10.0,125.0,40.0),certificate(0,0,0,140.0,255.0,45.0)]
		var failed: int = 0
		for grid: Dictionary in grids: failed+=grid.failures.size()
		var output := FileAccess.open("res://tests/balance/results/act1-adjustment-v03/angle-bound-verification.json",FileAccess.WRITE)
		output.store_string(JSON.stringify({"source_sha256":Factory.SOURCE_SHA256,"grids":grids,"certificates":angle_certs,"failures":failed},"\t"))
		output.close()
		print("V03 ANGLES 16128 checks, ",failed," failures")
		quit(1 if failed else 0)
		return
	var certs: Array = []
	var compact: bool = "--compact-search" in OS.get_cmdline_user_args()
	var long_search: bool = "--long-search" in OS.get_cmdline_user_args()
	var rank_sets: Array = [[0,0,0],[6,6,6],[8,8,8],[10,7,7],[7,10,7],[7,7,10]] if compact or long_search else [[0,0,0],[8,8,8],[10,8,0],[8,10,0],[7,7,10],[10,10,10]]
	var budget: float = 140.0 if long_search else (40.0 if compact else 80.0)
	var length: float = 255.0 if long_search else (150.0 if compact else 190.0)
	for ranks: Array in rank_sets:
		certs.append(certificate(ranks[0],ranks[1],ranks[2],budget,length))
	var grid: Dictionary = step_grid()
	var trials: Array = []
	if "--search" in OS.get_cmdline_user_args() or compact or long_search:
		for ranks: Array in rank_sets:
			for cadence: float in [0.25,0.12]:
				for threshold: float in ([0.48,0.5,0.52,0.55] if long_search else ([0.4,0.5,0.65] if compact else [0.5,0.65,0.8])):
					var trial: Dictionary = probe(ranks,cadence,threshold,1.0,budget,length)
					trials.append(trial)
					print("PROBE ",ranks," cadence",cadence," threshold",threshold," passed",trial.passed," peak",trial.peak_gain)
	var payload: Dictionary = {"source_sha256":Factory.SOURCE_SHA256,"candidate":candidate(budget,1.0,length),"certificates":certs,"step_grid":grid,"trials":trials}
	var output := FileAccess.open("res://tests/balance/results/act1-adjustment-v03/"+("recovery-bound-long-search.json" if long_search else ("recovery-bound-compact-search.json" if compact else "recovery-bound-search.json")),FileAccess.WRITE)
	output.store_string(JSON.stringify(payload,"\t"))
	output.close()
	print("V03 BOUND GRID ",grid.checks," checks, ",grid.failures.size()," failures")
	quit(1 if not grid.failures.is_empty() else 0)
