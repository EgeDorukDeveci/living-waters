extends Node3D

const FISH_SCALE := {
	"neon_tetra": Vector3(0.18, 0.065, 0.055),
	"betta_splendens": Vector3(0.28, 0.11, 0.08),
	"zebra_danio": Vector3(0.24, 0.075, 0.06),
	"peppered_cory": Vector3(0.28, 0.1, 0.075),
	"cherry_shrimp": Vector3(0.13, 0.05, 0.045)
}

var root_dir: String
var state_path: String
var command_path: String
var species_path: String
var state: Dictionary = {}
var species: Dictionary = {}
var fish_nodes: Dictionary = {}
var tank_size := Vector3(9.0, 4.0, 4.5)
var time_accum := 0.0
var panel: VBoxContainer
var water_labels: Dictionary = {}
var event_list: ItemList
var animal_list: ItemList
var status_label: Label
var overlay_label: Label
var water_material: StandardMaterial3D

func _ready() -> void:
	root_dir = _project_root()
	state_path = root_dir.path_join("runtime").path_join("aquarium_state.json")
	command_path = root_dir.path_join("runtime").path_join("command.json")
	species_path = root_dir.path_join("data").path_join("species").path_join("freshwater_v1.json")
	species = _load_species(species_path)
	_build_world()
	_build_ui()
	_load_state()

func _process(delta: float) -> void:
	time_accum += delta
	_animate_animals(delta)
	if time_accum > 1.0:
		time_accum = 0.0
		_load_state()

func _project_root() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").trim_suffix("/")
	return OS.get_executable_path().get_base_dir()

func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed

func _load_species(path: String) -> Dictionary:
	var payload = _load_json(path)
	var result := {}
	if typeof(payload) == TYPE_DICTIONARY:
		for item in payload.get("species", []):
			result[item["id"]] = item
	return result

func _load_state() -> void:
	var payload = _load_json(state_path)
	if typeof(payload) != TYPE_DICTIONARY:
		status_label.text = "Background ecosystem is starting..."
		return
	state = payload
	_sync_animals()
	_refresh_ui()

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#061116")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#6b9fb0")
	environment.ambient_light_energy = 0.34
	env.environment = environment
	add_child(env)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 3.3, 10.8)
	camera.rotation_degrees = Vector3(-14, 0, 0)
	add_child(camera)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-48, 31, 0)
	add_child(sun)

	water_material = StandardMaterial3D.new()
	water_material.albedo_color = Color(0.17, 0.52, 0.62, 0.32)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.roughness = 0.18
	water_material.metallic = 0.0

	var water := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = tank_size
	water.mesh = box
	water.material_override = water_material
	water.position = Vector3(0, 0, 0)
	add_child(water)

	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color("#223239")
	for y in [-tank_size.y / 2.0, tank_size.y / 2.0]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(tank_size.x + 0.25, 0.08, tank_size.z + 0.25)
		rail.mesh = rail_mesh
		rail.material_override = frame_material
		rail.position = Vector3(0, y, 0)
		add_child(rail)

	var substrate := MeshInstance3D.new()
	var substrate_mesh := BoxMesh.new()
	substrate_mesh.size = Vector3(tank_size.x, 0.18, tank_size.z)
	substrate.mesh = substrate_mesh
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color("#8d856d")
	substrate.material_override = sand
	substrate.position = Vector3(0, -tank_size.y / 2.0 + 0.08, 0)
	add_child(substrate)

	var plant_material := StandardMaterial3D.new()
	plant_material.albedo_color = Color("#6aa05e")
	for i in range(26):
		var plant := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.035
		cylinder.bottom_radius = 0.06
		cylinder.height = randf_range(0.45, 1.6)
		plant.mesh = cylinder
		plant.material_override = plant_material
		plant.position = Vector3(randf_range(-4.1, 4.1), -1.75 + cylinder.height / 2.0, randf_range(-1.8, 1.8))
		add_child(plant)

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var top := HBoxContainer.new()
	top.offset_left = 24
	top.offset_top = 18
	top.offset_right = 1256
	top.offset_bottom = 72
	root.add_child(top)

	var title := Label.new()
	title.text = "Living Waters"
	title.add_theme_font_size_override("font_size", 28)
	top.add_child(title)
	status_label = Label.new()
	status_label.text = "Waiting for ecosystem"
	status_label.add_theme_font_size_override("font_size", 14)
	top.add_child(status_label)

	var side_panel := PanelContainer.new()
	side_panel.offset_left = 662
	side_panel.offset_top = 88
	side_panel.offset_right = 954
	side_panel.offset_bottom = 690
	var side_style := StyleBoxFlat.new()
	side_style.bg_color = Color(0.035, 0.07, 0.08, 0.86)
	side_style.border_color = Color(0.24, 0.44, 0.45, 0.65)
	side_style.set_border_width_all(1)
	side_style.set_corner_radius_all(10)
	side_panel.add_theme_stylebox_override("panel", side_style)
	root.add_child(side_panel)

	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	side_panel.add_child(panel)

	var buttons := HBoxContainer.new()
	panel.add_child(buttons)
	var feed := Button.new()
	feed.text = "Feed modestly"
	feed.pressed.connect(func(): _write_command({"action": "feed", "amount": 0.42}))
	buttons.add_child(feed)
	var change := Button.new()
	change.text = "25% water change"
	change.pressed.connect(func(): _write_command({"action": "water_change", "fraction": 0.25}))
	buttons.add_child(change)

	overlay_label = Label.new()
	overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_label.custom_minimum_size = Vector2(262, 0)
	panel.add_child(overlay_label)

	for key in ["temperature_c", "ph", "oxygen_mg_l", "ammonia_mg_l", "nitrite_mg_l", "nitrate_mg_l"]:
		var label := Label.new()
		label.text = key
		panel.add_child(label)
		water_labels[key] = label

	var animal_title := Label.new()
	animal_title.text = "\nAnimals"
	animal_title.add_theme_font_size_override("font_size", 17)
	panel.add_child(animal_title)
	animal_list = ItemList.new()
	animal_list.custom_minimum_size = Vector2(320, 160)
	panel.add_child(animal_list)

	var event_title := Label.new()
	event_title.text = "\nTimeline"
	event_title.add_theme_font_size_override("font_size", 17)
	panel.add_child(event_title)
	event_list = ItemList.new()
	event_list.custom_minimum_size = Vector2(320, 190)
	panel.add_child(event_list)

func _write_command(command: Dictionary) -> void:
	command["timestamp"] = Time.get_datetime_string_from_system()
	DirAccess.make_dir_recursive_absolute(root_dir.path_join("runtime"))
	var file := FileAccess.open(command_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(command, "\t"))

func _sync_animals() -> void:
	for animal in state.get("animals", []):
		var id: String = str(animal.get("id", ""))
		if not animal.get("alive", true):
			if fish_nodes.has(id):
				fish_nodes[id].queue_free()
				fish_nodes.erase(id)
			continue
		if fish_nodes.has(id):
			continue
		var node := _make_fish(animal)
		fish_nodes[id] = node
		add_child(node)

func _make_fish(animal: Dictionary) -> Node3D:
	var spec = species.get(animal.get("species_id", ""), {})
	var body := Node3D.new()
	body.name = animal.get("name", "animal")
	body.set_meta("seed", int(animal.get("position_seed", 0)))
	body.set_meta("species_id", animal.get("species_id", ""))
	body.set_meta("zone", spec.get("swim_zone", "middle"))
	body.set_meta("phase", randf() * TAU)
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 24
	sphere.rings = 12
	mesh.mesh = sphere
	mesh.scale = FISH_SCALE.get(animal.get("species_id", ""), Vector3(0.2, 0.07, 0.06))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(spec.get("color", "#cccccc"))
	material.roughness = 0.42
	mesh.material_override = material
	body.add_child(mesh)
	var tail := MeshInstance3D.new()
	var tail_mesh := PrismMesh.new()
	tail_mesh.size = Vector3(0.18, 0.16, 0.03)
	tail.mesh = tail_mesh
	tail.position = Vector3(-0.2, 0, 0)
	var tail_mat := StandardMaterial3D.new()
	tail_mat.albedo_color = Color(spec.get("accent", "#ffffff"))
	tail.material_override = tail_mat
	body.add_child(tail)
	return body

func _animate_animals(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for id in fish_nodes.keys():
		var node: Node3D = fish_nodes[id]
		var seed: int = node.get_meta("seed")
		var zone: String = node.get_meta("zone")
		var rng_offset := float(seed % 97) / 97.0
		var z_base := -0.3
		if zone == "upper":
			z_base = -1.1
		elif zone == "bottom":
			z_base = 1.15
		var speed := 0.25 + (seed % 9) * 0.018
		var x := sin(t * speed + rng_offset * TAU) * 3.7
		var y := -0.2 + sin(t * speed * 1.7 + rng_offset) * 0.55
		if zone == "upper":
			y = 1.05 + sin(t * speed * 1.3 + rng_offset) * 0.35
		elif zone == "bottom":
			y = -1.52 + abs(sin(t * speed + rng_offset)) * 0.22
		var z := z_base + cos(t * speed * 0.8 + rng_offset * TAU) * 1.2
		var old := node.position
		node.position = node.position.lerp(Vector3(x, y, z), min(1, delta * 2.2))
		var direction := node.position - old
		if direction.length() > 0.001:
			node.look_at(node.position + direction, Vector3.UP)

func _refresh_ui() -> void:
	var summary = state.get("summary", {})
	var water = state.get("water", {})
	var status = summary.get("status", "stable")
	status_label.text = "%s - %d animals, %d stressed" % [
		status.capitalize(),
		int(summary.get("living_animals", 0)),
		int(summary.get("stressed_animals", 0))
	]
	overlay_label.text = "The ecosystem continues while this window is closed. The tray process owns biology, notifications, and offline catch-up."
	if water_material:
		var turbidity := float(water.get("turbidity", 0.0))
		water_material.albedo_color = Color(0.15 + turbidity * 0.25, 0.48, 0.58, 0.30 + turbidity * 0.28)
	for key in water_labels.keys():
		water_labels[key].text = _format_water(key, float(water.get(key, 0.0)))
	animal_list.clear()
	for animal in state.get("animals", []):
		var alive: bool = bool(animal.get("alive", true))
		var line := "%s - %s - stress %.0f%% - health %.0f%%" % [
			animal.get("name", "animal"),
			animal.get("behavior", "observing"),
			float(animal.get("acute_stress", 0.0)) * 100.0,
			float(animal.get("health", 1.0)) * 100.0
		]
		if not alive:
			line = "%s - died: %s" % [animal.get("name", "animal"), animal.get("cause_of_death", "unknown")]
		animal_list.add_item(line)
	event_list.clear()
	for item in state.get("events", []).slice(0, 8):
		event_list.add_item("%s  %s" % [item.get("severity", "info").capitalize(), item.get("title", "Event")])

func _format_water(key: String, value: float) -> String:
	match key:
		"temperature_c":
			return "Temperature: %.1f C" % value
		"ph":
			return "pH: %.2f" % value
		"oxygen_mg_l":
			return "Dissolved oxygen: %.1f mg/L" % value
		"ammonia_mg_l":
			return "Ammonia: %.3f mg/L" % value
		"nitrite_mg_l":
			return "Nitrite: %.3f mg/L" % value
		"nitrate_mg_l":
			return "Nitrate: %.1f mg/L" % value
	return "%s: %.2f" % [key, value]
