extends "res://tests/balance/adjustment_v02/gate_route.gd"

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var input_path: String = ""
	var select_job: String = ""
	for index: int in range(args.size()-1):
		if args[index]=="--input": input_path=args[index+1]
		elif args[index]=="--job": select_job=args[index+1]
	if not factory.build() or input_path.is_empty():
		quit(2)
		return
	var input := FileAccess.open(input_path,FileAccess.READ)
	var jobs: Dictionary = {}
	var results: Array = []
	var failures: int = 0
	while not input.eof_reached():
		var line: String = input.get_line()
		if line.is_empty(): continue
		var row: Dictionary = JSON.parse_string(line)
		if row.type=="metadata":
			for job: Dictionary in row.config.jobs: jobs[str(job.id)]=job
			continue
		if row.type!="run" or (not select_job.is_empty() and str(row.job_id)!=select_job): continue
		var job: Dictionary = jobs[str(row.job_id)]
		var profile: Dictionary = new_profile(job)
		var growth: Progression = profile.progression
		if not growth.restore(row.progression_start):
			printerr("Invalid recorded progression")
			quit(2)
			return
		profile.ranks=row.start_ranks.duplicate()
		profile.time=float(row.run_start_seconds)
		profile.earned=int(row.cumulative_xp)-int(row.earned_xp)
		growth.begin_run()
		var world := create_world(int(row.seed),job)
		configure_world(world,job.candidate)
		var stone: BoulderController = factory.create(world,job.candidate)
		apply_growth(stone,profile.ranks,job.candidate)
		stone.stamina=stone.max_stamina
		var raw: PackedByteArray = FileAccess.get_file_as_bytes(row.input_trace_gzip).decompress(int(row.steps),FileAccess.COMPRESSION_GZIP)
		var hash_context:=HashingContext.new()
		hash_context.start(HashingContext.HASH_SHA256)
		hash_context.update(raw)
		var matching: bool=hash_context.finish().hex_encode()==str(row.input_sha256)
		for command: int in raw:
			if growth.pending_points()>0: purchase(job,profile,stone)
			stone._step_v02(DT,(command&1)!=0,(command&2)!=0,(command&4)!=0)
			if int(floor(stone.peak/50.0))>growth.run_milestones: award(profile,stone)
		matching=matching and equivalent(stone.snapshot(),row.final_state) and equivalent(growth.snapshot(),row.progression_end)
		failures+=0 if matching else 1
		results.append({"job_id":row.job_id,"seed":row.seed,"run_index":row.run_index,"replayed_steps":raw.size(),"match":matching})
		print("GATE REPLAY ",row.job_id," seed",row.seed," run",row.run_index," ",matching)
	input.close()
	var output_path: String=input_path.get_basename()+"-replay.json"
	var out:=FileAccess.open(output_path,FileAccess.WRITE)
	out.store_string(JSON.stringify({"source":input_path,"failures":failures,"results":results},"\t"))
	out.close()
	quit(1 if failures else 0)

func equivalent(left: Variant,right: Variant) -> bool:
	if (left is float or left is int) and (right is float or right is int): return absf(float(left)-float(right))<0.0000001
	if left is Dictionary and right is Dictionary:
		if left.size()!=right.size(): return false
		for key: Variant in left:
			if not right.has(key) or not equivalent(left[key],right[key]): return false
		return true
	return left==right
