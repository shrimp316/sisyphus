extends "res://tests/mvp/difficulty_experiment.gd"
func run() -> void:
 policies=JSON.parse_string(FileAccess.get_file_as_string(policy_path())).policies
 var source="res://tests/mvp/results/difficulty-v1/pilot.jsonl"
 var row: Dictionary={}
 for line: String in FileAccess.get_file_as_string(source).split("\n"):
  if line.is_empty():continue
  var item: Dictionary=JSON.parse_string(line)
  if item.get("id","")=="default-zero-hold_D-101":row=item
 assert(not row.is_empty())
 var stone=DifficultyClimb.new(MountainManager.new(101,false,6,"clear"))
 stone.configure_difficulty(row.config)
 stone.apply_mastery_effects(row.modifiers)
 stone.restore(row.final_state)
 var start=stone.snapshot()
 for step: int in range(1200):stone.advance(DT,false,false,false)
 var recovered=stone.snapshot()
 var rng:=RandomNumberGenerator.new()
 rng.seed=101 ^ 0x4150494C
 var memory={"resting":false}
 var command=[false,false,false]
 for step: int in range(72000):
  if stone.peak>=250 or stone.state in ["result","summit"]:break
  if step%30==0:command=decide(stone,policies.regular,memory,rng,"regular")
  stone.advance(DT,command[0],command[1],command[2])
 var result={"source_run":row.id,"intervention":"Release all inputs 10 seconds, then unchanged regular synthetic policy; no position or stamina edits","start":start,"after_release":recovered,"final":stone.snapshot(),"reached_250":stone.peak>=250,"recovered_stamina":recovered.stamina,"seconds_after_intervention":stone.elapsed-float(start.elapsed),"scope":"Legal-input escape witness for this one observed timeout, not a global softlock proof"}
 var file=FileAccess.open("res://tests/mvp/results/difficulty-v1/release-escape-101.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(result,"\t"))
 print(JSON.stringify(result))
 quit(0)
