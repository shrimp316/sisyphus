extends SceneTree

class FaultMain extends "res://scripts/mvp/mastery_main.gd":
	var fail_writes: bool = false
	func _write_save_file(payload: Dictionary) -> Error:
		return ERR_CANT_CREATE if fail_writes else super._write_save_file(payload)

const DT: float = 1.0/120.0
var checks: int = 0
var failures: Array = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label)

func run() -> void:
	var main=FaultMain.new()
	main.save_path="user://mvp-fault-independent-"+Crypto.new().generate_random_bytes(12).hex_encode()+".json"
	check(not FileAccess.file_exists(main.save_path),"Fresh isolated namespace")
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	await process_frame
	main._reset_game()
	check(not main.persistence_failed and main.screen=="game","Initial durable game")
	var old_disk: String=FileAccess.get_file_as_string(main.save_path)
	main.boulder.distance=49.999
	main.boulder.peak=49.999
	main.boulder.velocity=1.0
	main.boulder.stamina=100.0
	var before_elapsed: float=main.boulder.elapsed
	main.fail_writes=true
	main.advance_gameplay(1.0/30.0,[true,false,false])
	check(main.persistence_failed,"Injected write failure detected")
	check(absf(main.boulder.elapsed-before_elapsed-DT)<0.0000001,"Failure stops before second fixed step in same rendered frame")
	check(main.mastery.available_exp==30,"First50m reward applied once in memory")
	check(FileAccess.get_file_as_string(main.save_path)==old_disk,"Failed save preserves old durable bytes")
	var frozen: Dictionary=main.boulder.snapshot()
	main.advance_gameplay(1.0,[true,true,false])
	check(main.boulder.snapshot()==frozen,"Further gameplay blocked after write failure")
	main.update_progression()
	check(main.mastery.available_exp==30,"Failure cannot duplicate reward through update")
	main.fail_writes=false
	check(main._persist_snapshot() and not main.persistence_failed,"Retry persists same memory state")
	check(int(JSON.parse_string(FileAccess.get_file_as_string(main.save_path)).mastery.available_exp)==30,"Retry durable reward exactly30")
	check(main._persist_snapshot() and main.mastery.available_exp==30,"Repeated successful save does not award")
	# Arrive using a fixture, then fail the actual commit write. Integration tests
	# separately reload every phase; this probe isolates failure in that write.
	main.boulder.distance=1000.0
	main.boulder.peak=1000.0
	main.boulder.velocity=0.0
	main.boulder.state="summit"
	main.boulder.ability.inertia_frontier=1000.0
	main.mastery.award_distance(1000.0,1000.0)
	main._start_prestige()
	while main.prestige_phase!="PRESTIGE_COMMIT": main._advance_prestige()
	old_disk=FileAccess.get_file_as_string(main.save_path)
	main.fail_writes=true
	main._advance_prestige()
	check(main.persistence_failed and main.prestige_phase=="PRESTIGE_COMMIT","Commit write failure holds journal phase")
	check(main.mastery.prestige_count==1 and main.mastery.threads_balance==1,"Commit reward applied once in memory")
	check(FileAccess.get_file_as_string(main.save_path)==old_disk,"Commit failure preserves precommit durable snapshot")
	main._advance_prestige()
	check(main.mastery.prestige_count==1 and main.mastery.threads_balance==1,"Failed phase cannot commit again")
	main.fail_writes=false
	check(main._persist_snapshot(),"Committed journal state saved on retry")
	main._advance_prestige()
	check(main.prestige_phase=="SEPHIROT_REVEAL" and main.mastery.prestige_count==1 and main.mastery.threads_balance==1,"Retry advances presentation without duplicate prestige")
	var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(main.save_path))
	check(saved.mastery.prestige_count==1 and saved.mastery.threads_balance==1,"One durable prestige and thread")
	var path: String=main.save_path
	main.free()
	await process_frame
	var result: Dictionary={"checks":checks,"failures":failures,"save_path":path,"scope":"Real file writes with injected ERR_CANT_CREATE before mutation of disk; native backend only. Summit arrival is a fixture. Browser quota/storage errors are a separate verification."}
	var output:=FileAccess.open("res://tests/mvp/results/storage-faults.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"\t"))
	output.close()
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
