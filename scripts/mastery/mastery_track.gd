extends Control
const Art = preload("res://scripts/mastery/mastery_art.gd")
const NodeScene = preload("res://godot/scenes/mastery/mastery_node.tscn")
const LABELS := {"strength": "근력", "endurance": "지구력", "breath": "호흡", "special": "특별 숙련"}
var track := ""
var views: Array = []
var connectors: Array[TextureRect] = []

func configure(kind: String, rows: Array[Dictionary]) -> void:
	track = kind
	name = "Track_" + kind
	mouse_filter = MOUSE_FILTER_IGNORE
	size = Vector2(1920, 1080)
	var center: float = float(rows[0].y)
	# Cover the source background's baked act plaques using supplied stone artwork.
	Art.image(self, "TrackPanel", "panels/track_panel_common.png", Rect2(108, center - 65, 1264, 128))
	if kind == "special":
		# special_panel includes a baked central Omega/frame that does not align
		# with the authoritative CSV. Reuse blank stone and the five exact placeholders.
		Art.image(self, "Badge", "navigation/header_text_blank_plaque.png", Rect2(115, center - 48, 250, 94))
	else:
		Art.image(self, "Badge", "panels/track_badge_%s.png" % kind, Rect2(115, center - 48, 250, 94))
	var title_x := 131.0 if kind == "special" else 221.0
	Art.label(self, "TrackName", LABELS[kind], Rect2(title_x, center - 23, 130, 46), "SisyphusNodeLabel")
	for i in rows.size() - 1:
		var left: Dictionary = rows[i]
		var right: Dictionary = rows[i + 1]
		connectors.append(Art.image(self, "Connector%d" % i, "nodes/connector_inactive.png", Rect2(float(left.x) + 35, center - 9, float(right.x) - float(left.x) - 70, 18)))
	for row: Dictionary in rows:
		var view = NodeScene.instantiate()
		add_child(view)
		view.configure(row)
		views.append(view)

func refresh_connectors() -> void:
	for i in connectors.size():
		var active: bool = views[i].state.get("purchased", false) and views[i + 1].state.get("purchased", false)
		connectors[i].texture = Art.texture("nodes/connector_active.png" if active else "nodes/connector_inactive.png")

func resonate() -> void:
	for i in views.size(): views[i].flash(i * 0.09)
