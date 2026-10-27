extends "res://tests/balance/adjustment_v03/simulator.gd"

const TRACE_ROOT: String="tests/balance/results/act1-adjustment-v03/"

# Archived absolute paths may belong to another checkout. Resolve only their
# v03-relative suffix; never follow a fallback outside this evidence directory.
func resolve_trace_path(reference: String) -> String:
	var normalized: String=reference.replace("\\","/")
	var marker: int=normalized.find(TRACE_ROOT)
	if marker<0 or (marker>0 and normalized.substr(marker-1,1)!="/"): return ""
	var suffix: String=normalized.substr(marker+TRACE_ROOT.length())
	if suffix.is_empty() or suffix.contains(":"): return ""
	for component: String in suffix.split("/",true):
		if component in ["",".",".."] or component.ends_with(".") or component.ends_with(" "): return ""
	var local: String="res://"+TRACE_ROOT+suffix
	var root: String=ProjectSettings.globalize_path("res://"+TRACE_ROOT).replace("\\","/")
	var absolute: String=ProjectSettings.globalize_path(local).replace("\\","/")
	if not absolute.begins_with(root) or not FileAccess.file_exists(local): return ""
	return local

# -- --input JSONL [--job ID]. Replays direct raw traces and observed stalls.
func run() -> void:
	var path: String=""
	var selected: String=""
	var args: PackedStringArray=OS.get_cmdline_user_args()
	for i: int in range(args.size()-1):
		if args[i]=="--input": path=args[i+1]
		elif args[i]=="--job": selected=args[i+1]
	if not factory.build() or path.is_empty():
		quit(2)
		return
	var file:=FileAccess.open(path,FileAccess.READ)
	var jobs: Dictionary={}
	var checks: Array=[]
	var failures: int=0
	while not file.eof_reached():
		var line: String=file.get_line()
		if line.is_empty(): continue
		var row: Dictionary=JSON.parse_string(line)
		if row.type=="metadata":
			policies=row.policies
			for job: Dictionary in row.config.jobs: jobs[str(job.id)]=job
			continue
		if row.type!="run" or (not selected.is_empty() and row.job_id!=selected): continue
		var job: Dictionary=jobs[str(row.job_id)]
		var world:=create_world(int(row.seed),job)
		configure_world(world,row.candidate)
		var stone: BoulderController=create_controller(world,row.candidate)
		apply_growth(stone,row.start_ranks,row.candidate)
		if row.has("input_trace_gzip"):
			var profile: Dictionary=new_profile(job)
			var progression: Progression=profile.progression
			if not progression.restore(row.progression_start):
				quit(2)
				return
			profile.ranks=row.start_ranks.duplicate()
			profile.time=float(row.run_start_seconds)
			profile.earned=int(row.cumulative_xp)-int(row.earned_xp)
			progression.begin_run()
			stone.restore(row.initial_state)
			var trace_path: String=resolve_trace_path(str(row.input_trace_gzip))
			if trace_path.is_empty():
				checks.append({"job_id":row.job_id,"seed":row.seed,"kind":"raw","match":false,"error":"Trace missing or outside permitted v03 evidence path"})
				failures+=1
				continue
			var raw: PackedByteArray=FileAccess.get_file_as_bytes(trace_path).decompress(int(row.steps),FileAccess.COMPRESSION_GZIP)
			var hash_context:=HashingContext.new()
			hash_context.start(HashingContext.HASH_SHA256)
			hash_context.update(raw)
			var matches: bool=raw.size()==int(row.steps) and hash_context.finish().hex_encode()==str(row.input_sha256)
			for input: int in raw:
				if not bool(row.diagnostic_fixture): purchase(job,profile,stone)
				stone._step_v02(DT,(input&1)!=0,(input&2)!=0,(input&4)!=0)
				if not bool(row.diagnostic_fixture) and int(stone.peak/50.0)>progression.run_milestones: award(profile,stone)
			matches=matches and equivalent(stone.snapshot(),row.final_state) and equivalent(progression.snapshot(),row.progression_end)
			checks.append({"job_id":row.job_id,"seed":row.seed,"kind":"raw","steps":raw.size(),"match":matches,"resolved_trace":trace_path})
			failures+=0 if matches else 1
		else:
			for stall: Dictionary in row.get("stall_events",[]):
				if not stall.input_history.is_empty(): stone.max_stamina=float(stall.input_history[0].stats[1])
				stone.restore(stall.replay_start_state)
				for segment: Dictionary in stall.input_history:
					stone.push_multiplier=float(segment.stats[0])
					stone.max_stamina=float(segment.stats[1])
					stone.recovery_multiplier=float(segment.stats[2])
					for step: int in range(int(segment.steps)):
						stone.advance(DT,segment.command[0],segment.command[1],segment.command[2])
				var matches: bool=equivalent(stone.snapshot(),stall.replay_end_state)
				checks.append({"job_id":row.job_id,"seed":row.seed,"kind":"stall","match":matches})
				failures+=0 if matches else 1
	var out:=FileAccess.open(path.get_basename()+"-replay.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"source":path,"checked":checks.size(),"failures":failures,"results":checks},"\t"))
	print("V03 REPLAY ",checks.size()," checked, ",failures," failures")
	quit(0 if not checks.is_empty() and failures==0 else 1)

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
