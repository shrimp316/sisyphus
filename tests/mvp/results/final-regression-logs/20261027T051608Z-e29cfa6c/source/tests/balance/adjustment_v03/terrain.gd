extends "res://tests/balance/adjustment_v02/terrain.gd"

var interval_overrides: Array = []

func configure_experiment(candidate: Dictionary) -> void:
	super.configure_experiment(candidate)
	interval_overrides = candidate.get("connection_layout",[]).duplicate(true)
	for gate: Dictionary in candidate.get("gates",[]):
		var geometry: Dictionary = gate.duplicate(true)
		geometry.shelf=false
		interval_overrides.append(geometry)
	if interval_overrides.is_empty(): return
	for interval: Dictionary in interval_overrides:
		_overlay(interval)
	var old_ledges: Array = ledges.duplicate(true)
	ledges.clear()
	for ledge: Dictionary in old_ledges:
		var old_position: float = float(ledge.distance)
		if old_position>=250.0 and not is_shelf(old_position):
			for segment: Dictionary in segments:
				if bool(segment.shelf) and float(segment.end)>old_position:
					ledge.distance=float(segment.start)+minf(2.0,(float(segment.end)-float(segment.start))*0.25)
					break
			ledge_relocations.append({"id":ledge.id,"old_m":old_position,"new_m":ledge.distance})
		# Keep relocated obstacles on an actual shelf and separate when possible.
		for other: Dictionary in ledges:
			if absf(float(other.distance)-float(ledge.distance))<0.5 and is_shelf(float(other.distance)+0.5):
				ledge.distance=float(other.distance)+0.5
		ledges.append(ledge)
	var original_points: Array = rest_points.duplicate()
	rest_points.clear()
	for original: float in original_points:
		var point: float = original
		if not is_shelf(point):
			for segment: Dictionary in segments:
				if bool(segment.shelf) and float(segment.end)>original:
					point=maxf(float(segment.start),float(segment.end)-0.25)
					break
		if is_shelf(point) and point not in rest_points: rest_points.append(point)
		if point!=original: rest_point_relocations.append({"old_m":original,"new_m":point})
	curve.clear_points()
	var point: Vector2 = Vector2.ZERO
	curve.add_point(point)
	for segment: Dictionary in segments:
		var angle: float = float(segment.angle)
		point+=Vector2(cos(angle),-sin(angle))*(float(segment.end)-float(segment.start))*PIXELS_PER_METER
		curve.add_point(point)

func _overlay(interval: Dictionary) -> void:
	var changed: Array[Dictionary] = []
	var start: float = float(interval.start_m)
	var finish: float = float(interval.end_m)
	for segment: Dictionary in segments:
		var a: float=float(segment.start)
		var b: float=float(segment.end)
		if b<=start or a>=finish:
			changed.append(segment)
			continue
		if a<start:
			var before: Dictionary=segment.duplicate(true)
			before.end=start
			changed.append(before)
		var middle: Dictionary=segment.duplicate(true)
		middle.start=maxf(a,start)
		middle.end=minf(b,finish)
		middle.shelf=bool(interval.get("shelf",false))
		middle.angle=0.0 if middle.shelf else deg_to_rad(float(interval.get("angle_degrees",0.0)))
		middle.surface=str(interval.get("surface","STONE"))
		middle.dry_override=bool(interval.get("dry",true))
		middle.experiment_interval=str(interval.get("id","connection"))
		changed.append(middle)
		if b>finish:
			var after: Dictionary=segment.duplicate(true)
			after.start=finish
			changed.append(after)
	segments=changed

func wet_at(position: float) -> bool:
	if bool(segment_at(position).get("dry_override",false)): return false
	return super.wet_at(position)

func experiment_layout() -> Array:
	return segments.duplicate(true)

func snapshot() -> Dictionary:
	var result: Dictionary=super.snapshot()
	result.runtime_segments=segments.duplicate(true)
	result.interval_overrides=interval_overrides.duplicate(true)
	result.runtime_ledges=ledges.duplicate(true)
	result.runtime_rest_points=rest_points.duplicate()
	return result
