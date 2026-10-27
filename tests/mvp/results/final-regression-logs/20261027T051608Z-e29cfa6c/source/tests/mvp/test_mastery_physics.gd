extends SceneTree

const Mastery = preload("res://scripts/mastery_boulder.gd")
const Golden = preload("res://tests/mvp/fixtures/legacy_boulder_controller.gd")
const DT: float=1.0/120.0
var checks: int=0
var failures: Array=[]

func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		printerr("FAIL ",label)
func near(a: float,b: float) -> bool: return absf(a-b)<0.0000001
func world(degrees: float=0.0,shelf: bool=false) -> MountainManager:
	var terrain:=MountainManager.new(101,false,6,"clear")
	terrain.segments=[{"start":0.0,"end":1000.0,"angle":deg_to_rad(degrees),"surface":"STONE","shelf":shelf,"chunk_id":"test","difficulty":1,"zone_index":0}]
	terrain.ledges.clear()
	terrain.rest_points.clear()
	return terrain
func stone(values: Dictionary={},degrees: float=0.0,shelf: bool=false):
	var result=Mastery.new(world(degrees,shelf))
	result.apply_mastery_effects({"effects":values,"purchased_nodes":[]})
	result.distance=100.0
	result.peak=100.0
	result.velocity=1.0
	return result
func same_base(a: Dictionary,b: Dictionary) -> bool:
	for key: String in a:
		if a[key] is float:
			if not near(a[key],b[key]): return false
		elif a[key]!=b[key]: return false
	return true

func run() -> void:
	# Original source fixture is owned by the independent verifier.
	for seed_value: int in [101,202,303]:
		var terrain:=MountainManager.new(seed_value,false,6)
		var golden=Golden.new(terrain)
		var base:=BoulderController.new(terrain)
		var neutral=Mastery.new(terrain)
		var rng:=RandomNumberGenerator.new()
		rng.seed=seed_value
		for step: int in range(1200):
			var command: int=rng.randi_range(0,3)
			for controller: Variant in [golden,base,neutral]: controller.advance(DT,command<2,command==1,command==2)
			if step%60==0:
				check(same_base(golden.snapshot(),base.snapshot()),"neutral base parity %d:%d"%[seed_value,step])
				check(same_base(golden.snapshot(),neutral.snapshot()),"neutral mastery parity %d:%d"%[seed_value,step])
	var s=stone({"push_bonus":0.15,"capacity_bonus":0.20,"recovery_bonus":0.05})
	s.stamina=67
	s.apply_mastery_effects({"effects":{"push_bonus":0.15,"capacity_bonus":0.20,"recovery_bonus":0.05}})
	s.apply_mastery_effects({"effects":{"push_bonus":0.15,"capacity_bonus":0.20,"recovery_bonus":0.05}})
	check(near(s.push_multiplier,1.15) and near(s.max_stamina,120) and near(s.stamina,67),"recalculate without stacking or capacity refill")
	s.advance(DT,true,false,false)
	check(near(s.push_force,2.6*1.15*1.1),"five strength nodes actual push")
	s=stone({"exert_multiplier":1.68,"sweet_push_multiplier":1.12})
	s.advance(DT,true,true,false)
	check(near(s.push_force,2.6*1.68*1.12),"shift and sweet force")
	s=stone({"start_requirement":1.23},30)
	s.velocity=0
	s.advance(DT,true,false,false)
	check(near(s.acceleration,2.6-1.5*1.23-0.2*1.23),"starting burden1.23")
	s=stone({"normal_drain_reduction":.03,"sweet_normal_drain_reduction":.05,"low_stamina_drain_reduction":.05},45)
	s.stamina=20
	s.advance(DT,true,false,false)
	check(near(s.stamina,20-1.7*.8*.87*DT),"additive normal sweet low consumption")
	s=stone({"exert_drain_reduction":.04},45)
	s.advance(DT,true,true,false)
	check(near(s.stamina,100-3*1.7*.8*.96*DT),"exert consumption")
	s=stone({"brace_drain_reduction":.05,"retreat_brace_drain_reduction":.05},45)
	s.velocity=-.5
	s.advance(DT,false,false,true)
	check(near(s.stamina,100-4*1.7*.9*DT),"brace reductions additive")
	s=stone({"low_stamina_push_multiplier":.7})
	s.stamina=19
	s.advance(DT,true,false,false)
	check(near(s.push_force,2.6*.7*1.1),"low stamina efficiency")
	s=stone({"gentle_coast_recovery":1},12)
	s.stamina=50
	s.advance(DT,false,false,false)
	check(near(s.stamina,50+DT),"BRE04 moving slope recovery")
	s=stone({"steep_stationary_recovery":1.5},25)
	s.velocity=.03
	s.stamina=50
	s.advance(DT,false,false,false)
	check(near(s.stamina,50+1.5*DT),"BRE05+09 near-stop floor")
	s=stone({"recovery_bonus":.05,"stationary_recovery_bonus":.10},25)
	s.velocity=0
	s.stamina=50
	s.advance(DT,false,false,false)
	check(near(s.stamina,50+7*1.15*DT),"BRE01+03 stationary additive recovery")
	s=stone({"non_exert_slip_decay_bonus":.1},25)
	var ordinary=stone({},25)
	s.slip=40
	ordinary.slip=40
	s.advance(DT,true,false,false)
	ordinary.advance(DT,true,false,false)
	check(near(ordinary.slip-s.slip,.4*DT),"BRE06 non-exert slip decay")
	s=stone({"ledge_push_bonus":.03})
	s.mountain.ledges.clear()
	s.mountain.ledges.append({"id":"test","distance":100.0,"required_push":1.6})
	s.distance=100.01
	s.push_force=2.6*1.6/1.03
	s._resolve_ledges(99.99)
	check(s.cleared_ledges.has("test"),"STR06 effective ledge force")
	_test_burst()
	_test_inertia()
	_test_rescues_and_specials()
	# External frame sizes both feed the same120Hz ability state machine.
	var a=stone({"post_exert_push_bonus":.05,"inertia_recovery_rate":2})
	var b=stone({"post_exert_push_bonus":.05,"inertia_recovery_rate":2})
	for frame: int in range(30): a.advance(1.0/30,true,true,false)
	for frame: int in range(144): b.advance(1.0/144,true,true,false)
	check(a.snapshot()==b.snapshot(),"30FPS144FPS ability and physics parity")
	print("MASTERY PHYSICS ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func _test_burst() -> void:
	var s=stone({"post_exert_push_bonus":.05})
	for step: int in range(48): s.advance(DT,true,true,false)
	s.velocity=1
	s.advance(DT,true,false,false)
	check(near(s.push_force,2.6*1.1*1.05),"STR10 qualifying release boost")
	for step: int in range(60): s.advance(DT,true,false,false)
	check(float(s.ability.burst_seconds)<=0.0,"STR10 ends after .5sec")
	for step: int in range(48): s.advance(DT,true,true,false)
	s.advance(DT,true,false,false)
	check(float(s.ability.burst_seconds)<=0.0,"STR10 cooldown blocks retrigger")
	var saved: Dictionary=s.snapshot()
	var clone=stone({"post_exert_push_bonus":.05})
	clone.restore(saved)
	check(clone.snapshot()==saved,"ability timer snapshot restore")

func _test_inertia() -> void:
	var s=stone({"inertia_recovery_rate":2})
	for step: int in range(2000):
		s.advance(DT,s.velocity<1.0,false,false)
		if s.ability.inertia_ready: break
	check(s.ability.inertia_ready,"BRE07 five new sweet-speed meters charge")
	s.stamina=50
	for step: int in range(121): s.advance(DT,false,false,false)
	check(near(s.ability.inertia_recovered,2.0) and s.ability.inertia_activations==1,"BRE07 one chance max2 actual stamina")
	for step: int in range(120): s.advance(DT,step%2==0,false,false)
	check(s.ability.inertia_activations==1,"BRE07 input toggle cannot recharge")
	s.distance=100
	s.velocity=1
	for step: int in range(600): s.advance(DT,s.velocity<1.0,false,false)
	check(not s.ability.inertia_ready,"BRE07 old ground cannot recharge")

func _test_rescues_and_specials() -> void:
	var s=stone({"exhaustion_rescue_fraction":.1},25)
	s.stamina=.00001
	s.advance(DT,true,true,false)
	check(near(s.stamina,10) and s.ability.exhaustion_rescue_used,"BRE10 positive-to-zero rescue")
	s.stamina=.00001
	s.advance(DT,true,true,false)
	check(s.stamina==0,"BRE10 once per run")
	var saved: Dictionary=s.snapshot()
	var clone=stone({"exhaustion_rescue_fraction":.1},25)
	clone.restore(saved)
	clone.stamina=.00001
	clone.advance(DT,true,true,false)
	check(clone.stamina==0,"BRE10 used state persists")
	s=stone({"exhaustion_rescue_fraction":.1},25)
	s.stamina=1
	s.slip=99.9999
	s.advance(DT,true,true,false)
	check(s.slip_remaining==.7 and near(s.stamina,10),"rescue never cancels Slip.7")
	s=stone({"exhaustion_rescue_fraction":.1,"special_crisis_reserve_fraction":.1},45)
	s.velocity=-4
	s.stamina=.001
	s.ability.reserve_charge=1
	s.advance(DT,true,true,false)
	check(s.state=="runaway" and not s.ability.exhaustion_rescue_used and s.ability.reserve_charge==1,"never rescues runaway-4")
	s=stone({"special_crisis_reserve_fraction":.1,"special_departure_drain_reduction":.1},0,true)
	s.velocity=0
	for step: int in range(240): s.advance(DT,false,false,false)
	check(s.ability.reserve_charge==1 and near(s.ability.departure_remaining,10),"SPC02SPC05 shelf2sec preparation")
	s.stamina=.00001
	s.advance(DT,true,true,false)
	check(near(s.stamina,10) and s.ability.reserve_charge==0,"SPC02 charged exhaustion rescue")
	s.velocity=0
	for step: int in range(360): s.advance(DT,false,false,false)
	check(s.ability.reserve_charge==0,"SPC02 same shelf cannot recharge")
	s.ability.departure_remaining=0
	for step: int in range(240): s.advance(DT,false,false,false)
	check(s.ability.departure_remaining==0,"SPC05 same shelf cannot prepare twice")
	s=stone({"special_departure_drain_reduction":.1},0,true)
	s.ability.departure_remaining=10
	s.advance(DT,true,false,false)
	check(near(s.stamina,100-.8*.8*.9*DT) and s.ability.departure_remaining<10,"SPC05 actual drain and forward distance consumption")
	s=stone({"special_brake_slip_reduction":15})
	s.ability.retreat_distance=1.01
	s.velocity=-.02
	s.slip=50
	s.advance(DT,false,false,true)
	check(s.velocity==0 and s.ability.brake_reductions==1 and s.slip<35,"SPC04 real1m brake reduction")
	s.advance(DT,false,false,true)
	check(s.ability.brake_reductions==1,"SPC04 no repeated event reward")
	s=stone({"special_scout_range":50,"special_warning_threshold":60})
	check(s.mastery_effects.special_scout_range==50 and s.mastery_effects.special_warning_threshold==60,"SPC01SPC03 presentation contract")
