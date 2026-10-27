extends "res://tests/mvp/s190_experiment.gd"

var verification_failures: Array=[]
var verification_checks: int=0

func verify(ok: bool,label: String) -> void:
	verification_checks+=1
	if not ok: verification_failures.append(label)

func equivalent(a: Variant,b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int): return absf(float(a)-float(b))<0.0000001
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i: int in range(a.size()):
			if not equivalent(a[i],b[i]): return false
		return true
	return a==b

func run() -> void:
	var world=TestTerrain.new(101,false,6,"clear")
	world.configure_experiment(CANDIDATE)
	var stone=TestBoulder.new(world)
	stone.distance=750.0
	stone.peak=750.0
	stone.velocity=1.0
	stone.stamina=50.0
	stone.opportunity_remaining=DT/2.0
	stone.advance(DT,false,false,false)
	verify(absf(stone.stamina-(50.0+7.0*DT/2.0))<0.0000001,"Partial last environmental opportunity is prorated")
	verify(stone.opportunity_remaining==0.0,"Partial opportunity exhausted")
	var before: float=stone.stamina
	stone.advance(DT,false,false,false)
	verify(stone.stamina==before,"No environmental recovery after quota ends")
	stone.distance=700.0
	stone.advance(DT,false,false,false)
	stone.distance=750.0
	stone.velocity=1.0
	stone.advance(DT,false,false,false)
	verify(stone.opportunity_remaining==0.0,"Reentry does not refill environmental opportunity")
	stone=TestBoulder.new(world)
	# Keep the exhausted probe inside the gate. At its750m boundary the stone
	# legitimately retreats to the outside shelf and may recover there.
	stone.distance=800.0
	stone.peak=800.0
	stone.stamina=0.0
	stone.advance(DT,true,false,false)
	verify(stone.opportunity_used==0.0 and stone.stamina==0.0,"Held exhausted effort cannot spend or obtain environment recovery")
	stone.advance(DT,false,false,false)
	verify(stone.opportunity_used==0.0 and stone.stamina==0.0,"Environment min1 blocks zero-stamina refill")
	var selected: Array[String]=["fixture-zero-regular_recovery-101","fixture-all30-skilled_recovery-101","route-all30-regular_recovery-101","route-breath18-skilled_recovery-101"]
	var source:=FileAccess.open("res://tests/mvp/results/s190/results.jsonl",FileAccess.READ)
	var replayed: int=0
	while not source.eof_reached():
		var line: String=source.get_line()
		if line.is_empty(): continue
		var row: Dictionary=JSON.parse_string(line)
		if row.type!="run" or row.id not in selected: continue
		world=TestTerrain.new(int(row.seed),false,6,"clear")
		world.configure_experiment(CANDIDATE)
		stone=TestBoulder.new(world)
		stone.apply_mastery_effects(row.modifiers)
		stone.restore(row.initial_state)
		var raw: PackedByteArray=FileAccess.get_file_as_bytes(row.input_trace).decompress(int(row.steps),FileAccess.COMPRESSION_GZIP)
		var digest:=HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(raw)
		verify(raw.size()==int(row.steps) and digest.finish().hex_encode()==row.input_sha256,"Raw SHA and steps "+row.id)
		for input: int in raw: stone.advance(DT,(input&1)!=0,(input&2)!=0,(input&4)!=0)
		verify(equivalent(stone.snapshot(),row.final_state) and equivalent(stone.experiment_snapshot(),row.gate),"Fresh-start full trace physical/ability/environment replay "+row.id)
		replayed+=1
	verify(replayed==4,"Four representative fixture/route success/failure traces replayed")
	var output:=FileAccess.open("res://tests/mvp/results/s190/verification.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":verification_checks,"failures":verification_failures,"raw_replays":replayed,"scope":"Fresh-start replays only. Test environmental opportunity is not serialized by ordinary controller snapshot, so mid-gate checkpoint restore is not claimed."},"\t"))
	output.close()
	print("S190 verification ",verification_checks," checks, ",verification_failures.size()," failures")
	quit(0 if verification_failures.is_empty() else 1)
