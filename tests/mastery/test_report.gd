extends RefCounted
## Shared reporting only; assertions remain in independent verification suites.
var checks: int = 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func finish(suite: String, details: Dictionary = {}) -> int:
	var report: Dictionary = {"suite": suite, "checks": checks, "failures": failures, "passed": failures.is_empty(), "engine": Engine.get_version_info().string, "display": DisplayServer.get_name()}
	report.merge(details)
	var directory: String = "res://tests/mastery/results/v12/verification"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory.path_join(suite + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	return 0 if failures.is_empty() else 1
