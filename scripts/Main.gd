extends Control

const PANEL_WIDTH := 336.0
const EDGE := 28.0
const TOP_BAR := 82.0
const SAND_HEIGHT := 74.0
const COMMAND_FEED := {"action": "feed", "amount": 0.42}
const COMMAND_WATER_CHANGE := {"action": "water_change", "fraction": 0.25}

var root_dir: String
var state_path: String
var command_path: String
var species_path: String
var state: Dictionary = {}
var species: Dictionary = {}
var animal_visuals: Dictionary = {}
var fish_textures: Dictionary = {}
var scape_textures: Dictionary = {}
var time_accum := 0.0

var panel: VBoxContainer
var water_labels: Dictionary = {}
var event_list: ItemList
var animal_list: ItemList
var species_select: OptionButton
var status_label: Label
var summary_label: Label
var scape_label: Label
var tool_label: Label
var title_label: Label
var animal_ids: Array = []
var selected_animal_id := ""
var selected_scape_tool: Dictionary = {}
var selected_scape_object_id := ""

func _ready() -> void:
	root_dir = _project_root()
	state_path = root_dir.path_join("runtime").path_join("aquarium_state.json")
	command_path = root_dir.path_join("runtime").path_join("command.json")
	species_path = root_dir.path_join("data").path_join("species").path_join("freshwater_v1.json")
	species = _load_species(species_path)
	_load_sprite_assets()
	_build_ui()
	_load_state()
	queue_redraw()

func _process(delta: float) -> void:
	time_accum += delta
	_animate_animals(delta)
	if time_accum > 1.0:
		time_accum = 0.0
		_load_state()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_ui()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse: Vector2 = event.position
		var inner := _tank_inner()
		if not inner.has_point(mouse):
			return
		var normalized := Vector2(
			clamp((mouse.x - inner.position.x) / inner.size.x, 0.0, 1.0),
			clamp((mouse.y - inner.position.y) / inner.size.y, 0.0, 1.0)
		)
		var hit := _hit_scape_object(mouse)
		if selected_scape_tool.is_empty() and hit != "":
			selected_scape_object_id = hit
			if tool_label:
				tool_label.text = "Selected scape object. Click another valid spot to move it, or remove it."
			return
		if selected_scape_object_id != "":
			if _client_position_valid("", "", normalized):
				_write_command({"action": "move_scape_item", "object_id": selected_scape_object_id, "x": normalized.x, "y": normalized.y})
			return
		if selected_scape_tool.is_empty():
			return
		var category := str(selected_scape_tool.get("category", ""))
		var item_type := str(selected_scape_tool.get("type", ""))
		if not _client_position_valid(category, item_type, normalized):
			return
		_write_command({"action": "place_scape_item", "category": category, "type": item_type, "x": normalized.x, "y": normalized.y, "scale": 1.0})

func _client_position_valid(category: String, item_type: String, normalized: Vector2) -> bool:
	if category == "":
		return true
	if category == "plants" and item_type == "red_root_floaters":
		if normalized.y > 0.22:
			if tool_label:
				tool_label.text = "Floaters need the surface, not the substrate."
			return false
		return true
	if category == "plants" and normalized.y < 0.70:
		if tool_label:
			tool_label.text = "Rooted plants cannot be placed in open water."
		return false
	if category in ["rocks", "wood", "corals"] and normalized.y < 0.52:
		if tool_label:
			tool_label.text = "That item needs a surface, not open water."
		return false
	return true

func _draw() -> void:
	_draw_room()
	_draw_aquarium()
	_draw_hardscape()
	_draw_corals()
	_draw_plants()
	_draw_bubbles()
	_draw_animals()
	_draw_front_glass()

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
	return JSON.parse_string(file.get_as_text())

func _load_species(path: String) -> Dictionary:
	var payload = _load_json(path)
	var result := {}
	if typeof(payload) == TYPE_DICTIONARY:
		for item in payload.get("species", []):
				result[item["id"]] = item
	return result

func _load_sprite_assets() -> void:
	var fish_ids := species.keys()
	if fish_ids.is_empty():
		fish_ids = [
			"neon_tetra", "betta_splendens", "zebra_danio", "peppered_cory", "cherry_shrimp",
			"harlequin_rasbora", "fancy_guppy", "honey_gourami", "kuhli_loach"
		]
	for id in fish_ids:
		var texture := _load_png_texture("res://assets/sprites/fish/%s.png" % id)
		if texture:
			fish_textures[id] = texture
	for id in [
		"river_stone", "moss_stone", "dragon_stone", "branch_driftwood", "root_driftwood",
		"dwarf_hairgrass", "java_fern", "anubias", "vallisneria", "red_root_floaters",
		"live_rock", "reef_arch", "halimeda_macroalgae", "turtle_grass",
		"zoanthids", "mushroom_coral", "green_star_polyps", "torch_coral"
	]:
		var texture := _load_png_texture("res://assets/sprites/scape/%s.png" % id)
		if texture:
			scape_textures[id] = texture

func _load_png_texture(path: String) -> Texture2D:
	if FileAccess.file_exists(path + ".import"):
		var imported := ResourceLoader.load(path)
		if imported is Texture2D:
			return imported
	var image := Image.new()
	var error := image.load(path)
	if error == OK:
		return ImageTexture.create_from_image(image)
	return null

func _load_state() -> void:
	var payload = _load_json(state_path)
	if typeof(payload) != TYPE_DICTIONARY:
		status_label.text = "Starting ecosystem"
		summary_label.text = "Waiting for the background caretaker to publish the first aquarium state."
		return
	state = payload
	_sync_animals()
	_refresh_ui()
	_refresh_species_options()

func _build_ui() -> void:
	title_label = Label.new()
	title_label.text = "Living Waters"
	title_label.position = Vector2(EDGE + 52, 24)
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", Color("#f5efe3"))
	add_child(title_label)

	status_label = Label.new()
	status_label.text = "Waiting for ecosystem"
	status_label.position = Vector2(EDGE + 56, 58)
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#9bc7c9"))
	add_child(status_label)

	var side_panel := PanelContainer.new()
	side_panel.name = "SidePanel"
	var side_style := StyleBoxFlat.new()
	side_style.bg_color = Color(0.055, 0.071, 0.083, 0.92)
	side_style.border_color = Color("#2c5960")
	side_style.set_border_width_all(1)
	side_style.set_corner_radius_all(16)
	side_panel.add_theme_stylebox_override("panel", side_style)
	add_child(side_panel)

	var scroll := ScrollContainer.new()
	scroll.name = "SideScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.offset_left = 0
	scroll.offset_top = 0
	scroll.offset_right = 0
	scroll.offset_bottom = 0
	side_panel.add_child(scroll)

	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)
	panel.offset_left = 18
	panel.offset_top = 18
	panel.offset_right = -18
	panel.offset_bottom = -18
	scroll.add_child(panel)

	var panel_title := Label.new()
	panel_title.text = "Tank Care"
	panel_title.add_theme_font_size_override("font_size", 23)
	panel_title.add_theme_color_override("font_color", Color("#f5efe3"))
	panel.add_child(panel_title)

	summary_label = Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.add_theme_color_override("font_color", Color("#b7d5d1"))
	panel.add_child(summary_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	panel.add_child(buttons)

	var feed := Button.new()
	feed.text = "Feed"
	feed.custom_minimum_size = Vector2(134, 38)
	feed.pressed.connect(func(): _write_command(COMMAND_FEED.duplicate()))
	buttons.add_child(feed)

	var change := Button.new()
	change.text = "Water change"
	change.custom_minimum_size = Vector2(142, 38)
	change.pressed.connect(func(): _write_command(COMMAND_WATER_CHANGE.duplicate()))
	buttons.add_child(change)

	for key in ["temperature_c", "ph", "oxygen_mg_l", "ammonia_mg_l", "nitrite_mg_l", "nitrate_mg_l"]:
		var label := Label.new()
		label.text = key
		label.add_theme_color_override("font_color", Color("#d8eee9"))
		panel.add_child(label)
		water_labels[key] = label

	var system_row := HBoxContainer.new()
	system_row.add_theme_constant_override("separation", 8)
	panel.add_child(system_row)
	var fresh := Button.new()
	fresh.text = "Freshwater"
	fresh.custom_minimum_size = Vector2(142, 32)
	fresh.pressed.connect(func(): _write_command({"action": "switch_system", "system": "freshwater"}))
	system_row.add_child(fresh)
	var reef := Button.new()
	reef.text = "Saltwater"
	reef.custom_minimum_size = Vector2(142, 32)
	reef.pressed.connect(func(): _write_command({"action": "switch_system", "system": "saltwater"}))
	system_row.add_child(reef)

	var animal_title_controls := Label.new()
	animal_title_controls.text = "Add Animals"
	animal_title_controls.add_theme_font_size_override("font_size", 18)
	animal_title_controls.add_theme_color_override("font_color", Color("#f5efe3"))
	panel.add_child(animal_title_controls)

	species_select = OptionButton.new()
	species_select.custom_minimum_size = Vector2(300, 32)
	panel.add_child(species_select)
	_refresh_species_options()

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	panel.add_child(add_row)
	var add_good := Button.new()
	add_good.text = "Acclimate"
	add_good.custom_minimum_size = Vector2(142, 32)
	add_good.pressed.connect(func(): _add_selected_animal(true))
	add_row.add_child(add_good)
	var add_bad := Button.new()
	add_bad.text = "Skip acclimation"
	add_bad.custom_minimum_size = Vector2(142, 32)
	add_bad.pressed.connect(func(): _add_selected_animal(false))
	add_row.add_child(add_bad)

	var scape_title := Label.new()
	scape_title.text = "Scape Studio"
	scape_title.add_theme_font_size_override("font_size", 18)
	scape_title.add_theme_color_override("font_color", Color("#f5efe3"))
	panel.add_child(scape_title)

	scape_label = Label.new()
	scape_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scape_label.add_theme_font_size_override("font_size", 12)
	scape_label.add_theme_color_override("font_color", Color("#a8c8bd"))
	panel.add_child(scape_label)

	tool_label = Label.new()
	tool_label.text = "Choose a scape item, then click inside the tank."
	tool_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tool_label.add_theme_font_size_override("font_size", 12)
	tool_label.add_theme_color_override("font_color", Color("#e7d08a"))
	panel.add_child(tool_label)

	var scape_grid := GridContainer.new()
	scape_grid.columns = 2
	scape_grid.add_theme_constant_override("h_separation", 8)
	scape_grid.add_theme_constant_override("v_separation", 6)
	panel.add_child(scape_grid)
	_add_scape_button(scape_grid, "River stone", "rocks", "river_stone")
	_add_scape_button(scape_grid, "Moss stone", "rocks", "moss_stone")
	_add_scape_button(scape_grid, "Live rock", "rocks", "live_rock")
	_add_scape_button(scape_grid, "Reef arch", "rocks", "reef_arch")
	_add_scape_button(scape_grid, "Branch log", "wood", "branch_driftwood")
	_add_scape_button(scape_grid, "Root wood", "wood", "root_driftwood")
	_add_scape_button(scape_grid, "Hairgrass", "plants", "dwarf_hairgrass")
	_add_scape_button(scape_grid, "Vallisneria", "plants", "vallisneria")
	_add_scape_button(scape_grid, "Java fern", "plants", "java_fern")
	_add_scape_button(scape_grid, "Floaters", "plants", "red_root_floaters")
	_add_scape_button(scape_grid, "Halimeda", "plants", "halimeda_macroalgae")
	_add_scape_button(scape_grid, "Zoanthids", "corals", "zoanthids")
	_add_scape_button(scape_grid, "Mushroom coral", "corals", "mushroom_coral")
	_add_scape_button(scape_grid, "Torch coral", "corals", "torch_coral")

	var reset_scape := Button.new()
	reset_scape.text = "Reset greenscape"
	reset_scape.custom_minimum_size = Vector2(300, 32)
	reset_scape.pressed.connect(func(): _write_command({"action": "reset_scape"}))
	panel.add_child(reset_scape)

	var animal_title := Label.new()
	animal_title.text = "Animals"
	animal_title.add_theme_font_size_override("font_size", 18)
	animal_title.add_theme_color_override("font_color", Color("#f5efe3"))
	panel.add_child(animal_title)

	animal_list = ItemList.new()
	animal_list.custom_minimum_size = Vector2(300, 112)
	animal_list.item_selected.connect(func(index): _select_animal(index))
	panel.add_child(animal_list)

	var remove_animal := Button.new()
	remove_animal.text = "Remove selected animal"
	remove_animal.custom_minimum_size = Vector2(300, 32)
	remove_animal.pressed.connect(func(): _remove_selected_animal())
	panel.add_child(remove_animal)

	var remove_scape := Button.new()
	remove_scape.text = "Remove selected scape"
	remove_scape.custom_minimum_size = Vector2(300, 32)
	remove_scape.pressed.connect(func(): _remove_selected_scape())
	panel.add_child(remove_scape)

	var event_title := Label.new()
	event_title.text = "Timeline"
	event_title.add_theme_font_size_override("font_size", 18)
	event_title.add_theme_color_override("font_color", Color("#f5efe3"))
	panel.add_child(event_title)

	event_list = ItemList.new()
	event_list.custom_minimum_size = Vector2(300, 108)
	panel.add_child(event_list)
	_layout_ui()

func _add_scape_button(parent: Container, text: String, category: String, item_type: String, quantity: int = 1) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(142, 30)
	button.pressed.connect(func(): _choose_scape_tool(category, item_type, text))
	parent.add_child(button)

func _layout_ui() -> void:
	var side_panel := get_node_or_null("SidePanel") as PanelContainer
	if side_panel:
		side_panel.position = Vector2(size.x - PANEL_WIDTH - EDGE, TOP_BAR)
		side_panel.size = Vector2(PANEL_WIDTH, max(560.0, size.y - TOP_BAR - EDGE))
		var scroll := side_panel.get_node_or_null("SideScroll") as ScrollContainer
		if scroll:
			scroll.size = side_panel.size

func _refresh_species_options() -> void:
	if not species_select:
		return
	var current_system := str(state.get("water", {}).get("system", "freshwater"))
	species_select.clear()
	for id in species.keys():
		var spec: Dictionary = species[id]
		if str(spec.get("water_type", "freshwater")) != current_system:
			continue
		species_select.add_item("%s (%s)" % [spec.get("common_name", id), spec.get("swim_zone", "middle")])
		species_select.set_item_metadata(species_select.item_count - 1, id)

func _add_selected_animal(acclimated: bool) -> void:
	if species_select.item_count <= 0:
		return
	var id := str(species_select.get_item_metadata(species_select.selected))
	var spec: Dictionary = species.get(id, {})
	var minutes := int(spec.get("acclimation_minutes", 30)) if acclimated else 0
	_write_command({"action": "add_animal", "species_id": id, "acclimation_minutes": minutes})

func _select_animal(index: int) -> void:
	if index >= 0 and index < animal_ids.size():
		selected_animal_id = str(animal_ids[index])

func _remove_selected_animal() -> void:
	if selected_animal_id == "":
		return
	_write_command({"action": "remove_animal", "animal_id": selected_animal_id})
	selected_animal_id = ""

func _choose_scape_tool(category: String, item_type: String, label: String) -> void:
	selected_scape_tool = {"category": category, "type": item_type, "label": label}
	selected_scape_object_id = ""
	if tool_label:
		tool_label.text = "Placing %s. Click inside the tank." % label

func _remove_selected_scape() -> void:
	if selected_scape_object_id == "":
		return
	_write_command({"action": "remove_scape_item", "object_id": selected_scape_object_id})
	selected_scape_object_id = ""

func _write_command(command: Dictionary) -> void:
	command["timestamp"] = Time.get_datetime_string_from_system()
	DirAccess.make_dir_recursive_absolute(root_dir.path_join("runtime"))
	var file := FileAccess.open(command_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(command, "\t"))

func _sync_animals() -> void:
	var alive_ids := {}
	for animal in state.get("animals", []):
		var id: String = str(animal.get("id", ""))
		if id == "":
			continue
		if not animal.get("alive", true):
			continue
		alive_ids[id] = true
		if animal_visuals.has(id):
			continue
		var seed := int(animal.get("position_seed", 0))
		var spec = species.get(animal.get("species_id", ""), {})
		var visual := {
			"seed": seed,
			"species_id": animal.get("species_id", ""),
			"phase": float(seed % 628) / 100.0,
			"pos": _seeded_point(seed, spec.get("swim_zone", "middle")),
			"target": _seeded_point(seed + 31, spec.get("swim_zone", "middle")),
			"facing": 1.0
		}
		animal_visuals[id] = visual
	for id in animal_visuals.keys():
		if not alive_ids.has(id):
			animal_visuals.erase(id)

func _animate_animals(delta: float) -> void:
	var aquarium := _aquarium_rect()
	if aquarium.size.x <= 0:
		return
	var animals: Array = state.get("animals", [])
	for animal in animals:
		var id: String = str(animal.get("id", ""))
		if not animal_visuals.has(id):
			continue
		var visual: Dictionary = animal_visuals[id]
		var spec = species.get(animal.get("species_id", ""), {})
		var seed: int = visual.get("seed", 1)
		var zone: String = spec.get("swim_zone", "middle")
		var activity := float(spec.get("activity", 0.5))
		var pos: Vector2 = visual["pos"]
		var target: Vector2 = visual["target"]
		if pos.distance_to(target) < 16.0:
			visual["target"] = _moving_target(seed, zone)
			target = visual["target"]
		var speed: float = lerp(18.0, 58.0, activity)
		var next := pos.move_toward(target, speed * delta)
		visual["facing"] = 1.0 if target.x >= pos.x else -1.0
		visual["pos"] = next
		visual["phase"] = float(visual["phase"]) + delta * (2.0 + activity * 2.6)
		animal_visuals[id] = visual

func _aquarium_rect() -> Rect2:
	var right_edge := size.x - PANEL_WIDTH - EDGE * 2.0
	return Rect2(EDGE, TOP_BAR, max(520.0, right_edge), max(480.0, size.y - TOP_BAR - EDGE))

func _tank_inner() -> Rect2:
	var aquarium := _aquarium_rect()
	return aquarium.grow(-20.0)

func _seeded_point(seed: int, zone: String) -> Vector2:
	var inner := _tank_inner()
	var x_ratio := float((seed * 37) % 1000) / 1000.0
	var y_ratio := float((seed * 83 + 211) % 1000) / 1000.0
	return Vector2(
		inner.position.x + lerp(58.0, inner.size.x - 58.0, x_ratio),
		_zone_y(zone, y_ratio)
	)

func _moving_target(seed: int, zone: String) -> Vector2:
	var t := Time.get_ticks_msec() / 1000.0
	var inner := _tank_inner()
	var x := inner.position.x + 52.0 + fposmod(sin(t * 0.7 + seed) * 0.5 + 0.5 + float(seed % 13) * 0.073, 1.0) * (inner.size.x - 104.0)
	var y := _zone_y(zone, fposmod(cos(t * 0.53 + seed * 0.31) * 0.5 + 0.5, 1.0))
	return Vector2(x, y)

func _zone_y(zone: String, ratio: float) -> float:
	var inner := _tank_inner()
	var water_bottom := inner.position.y + inner.size.y - SAND_HEIGHT
	match zone:
		"upper":
			return lerp(inner.position.y + 58.0, inner.position.y + inner.size.y * 0.34, ratio)
		"bottom":
			return lerp(water_bottom - 34.0, water_bottom - 10.0, ratio)
	return lerp(inner.position.y + inner.size.y * 0.32, water_bottom - 62.0, ratio)

func _draw_room() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#071013"))
	var aquarium := _aquarium_rect()
	draw_rect(Rect2(0, 0, size.x, TOP_BAR + 22.0), Color("#0b1418"))
	draw_rect(Rect2(aquarium.position + Vector2(-6, -6), aquarium.size + Vector2(12, 12)), Color("#0f1d21"))
	draw_rect(Rect2(EDGE, 26, 15, 20), Color("#ff776a"))
	draw_rect(Rect2(EDGE + 20, 18, 15, 28), Color("#5bc5dc"))
	draw_rect(Rect2(EDGE + 40, 12, 15, 34), Color("#f2cf68"))

func _draw_aquarium() -> void:
	var tank := _aquarium_rect()
	var inner := _tank_inner()
	var style := _aquascape_style()
	draw_rect(tank, Color("#15262b"), true)
	for i in range(10):
		var ratio := float(i) / 10.0
		var band := Rect2(inner.position.x, inner.position.y + inner.size.y * ratio, inner.size.x, inner.size.y / 10.0 + 1.0)
		var system := str(state.get("water", {}).get("system", "freshwater"))
		var top_color := Color("#1f665e") if style == "greenscape" else Color("#1e6f8c")
		var bottom_color := Color("#102c33") if system == "freshwater" else Color("#0c344c")
		var color := bottom_color.lerp(top_color, 1.0 - ratio)
		color.a = 0.96
		draw_rect(band, color, true)
	var water = state.get("water", {})
	var turbidity: float = clamp(float(water.get("turbidity", 0.0)), 0.0, 1.0)
	var ammonia: float = clamp(float(water.get("ammonia_mg_l", 0.0)) * 2.0, 0.0, 1.0)
	var nitrate: float = clamp(max(0.0, float(water.get("nitrate_mg_l", 0.0)) - 20.0) / 40.0, 0.0, 1.0)
	if turbidity > 0.02:
		draw_rect(inner, Color(0.46, 0.36, 0.18, turbidity * 0.18), true)
	if ammonia > 0.02:
		draw_rect(inner, Color(0.78, 0.70, 0.30, ammonia * 0.16), true)
	if nitrate > 0.02:
		draw_rect(inner, Color(0.22, 0.56, 0.22, nitrate * 0.14), true)
	for i in range(3):
		var y := inner.position.y + 24.0 + i * 18.0 + sin(Time.get_ticks_msec() / 900.0 + i) * 3.0
		_draw_wave(Vector2(inner.position.x + 18.0, y), inner.size.x - 36.0, Color(0.74, 0.94, 0.98, 0.16), 2.0 + i)
	var sand := Rect2(inner.position.x, inner.end.y - SAND_HEIGHT, inner.size.x, SAND_HEIGHT)
	draw_rect(sand, Color("#786d54"), true)
	for i in range(70):
		var x := inner.position.x + fposmod(i * 47.0, inner.size.x)
		var y := sand.position.y + 12.0 + fposmod(i * 19.0, sand.size.y - 16.0)
		draw_circle(Vector2(x, y), 1.4 + float(i % 4) * 0.45, Color(0.90, 0.79, 0.56, 0.34))
	draw_rect(tank, Color("#416973"), false, 3.0)
	draw_rect(inner, Color(1, 1, 1, 0.045), false, 1.0)

func _aquascape_style() -> String:
	return str(state.get("aquarium", {}).get("aquascape_style", "greenscape"))

func _scape_items(category: String) -> Array:
	var scape = state.get("aquarium", {}).get("scape", {})
	var result := []
	if typeof(scape) == TYPE_DICTIONARY and scape.has(category):
		for item in scape.get(category, []):
			result.append(item)
		for obj in scape.get("objects", []):
			if str(obj.get("category", "")) == category:
				var copy: Dictionary = obj.duplicate()
				copy["quantity"] = 1
				result.append(copy)
		return result
	if category == "rocks":
		return [{"type": "river_stone", "quantity": 5}, {"type": "moss_stone", "quantity": 2}]
	if category == "wood":
		return [{"type": "branch_driftwood", "quantity": 2}, {"type": "root_driftwood", "quantity": 1}]
	if category == "plants":
		return [
			{"type": "dwarf_hairgrass", "quantity": 18},
			{"type": "java_fern", "quantity": 5},
			{"type": "anubias", "quantity": 4},
			{"type": "vallisneria", "quantity": 8},
			{"type": "red_root_floaters", "quantity": 6}
		]
	return []

func _object_pos(item: Dictionary, fallback: Vector2) -> Vector2:
	if item.has("x") and item.has("y"):
		var inner := _tank_inner()
		return inner.position + Vector2(float(item["x"]) * inner.size.x, float(item["y"]) * inner.size.y)
	return fallback

func _hit_scape_object(mouse: Vector2) -> String:
	var scape = state.get("aquarium", {}).get("scape", {})
	if typeof(scape) != TYPE_DICTIONARY:
		return ""
	for obj in scape.get("objects", []):
		var pos := _object_pos(obj, Vector2.ZERO)
		var radius := 42.0 * float(obj.get("scale", 1.0))
		if pos.distance_to(mouse) <= radius:
			return str(obj.get("id", ""))
	return ""

func _rock_color(kind: String) -> Color:
	match kind:
		"moss_stone":
			return Color("#4f6752")
		"dragon_stone":
			return Color("#776b55")
		_:
			return Color("#4d5a50")

func _draw_wave(start: Vector2, width: float, color: Color, phase: float) -> void:
	var points := PackedVector2Array()
	for i in range(42):
		var x := start.x + width * float(i) / 41.0
		var y := start.y + sin(float(i) * 0.72 + phase + Time.get_ticks_msec() / 780.0) * 4.0
		points.push_back(Vector2(x, y))
	draw_polyline(points, color, 2.0, true)

func _draw_hardscape() -> void:
	var inner := _tank_inner()
	var sand_top := inner.end.y - SAND_HEIGHT
	var center := inner.position.x + inner.size.x * 0.45
	var rock_index := 0
	for item in _scape_items("rocks"):
		var quantity := int(item.get("quantity", 0))
		var kind := str(item.get("type", "river_stone"))
		for n in range(quantity):
			var i := rock_index + n
			var radius := 18.0 + float((i * 11) % 34) * float(item.get("scale", 1.0))
			var x := center + float(i - quantity) * 31.0 + sin(i * 2.1) * 18.0
			var y := sand_top + 18.0 + float(i % 3) * 13.0
			var pos := _object_pos(item, Vector2(x, y))
			var stone_color := _rock_color(kind)
			if not _draw_scape_sprite(kind, pos, Vector2(radius * 2.45, radius * 2.15), i % 2 == 0):
				_draw_rock(pos, radius, stone_color, i)
		rock_index += quantity
	var wood_index := 0
	for item in _scape_items("wood"):
		var quantity := int(item.get("quantity", 0))
		var kind := str(item.get("type", "branch_driftwood"))
		for n in range(quantity):
			var branch_count := 3 if kind == "branch_driftwood" else 5
			var root := Vector2(inner.position.x + inner.size.x * (0.44 + fposmod(float(wood_index) * 0.13, 0.22)), sand_top + 24.0)
			root = _object_pos(item, root)
			if not _draw_scape_sprite(kind, root + Vector2(0, -52), Vector2(190, 150), wood_index % 2 == 1):
				_draw_driftwood(root, branch_count, wood_index)
			wood_index += 1

func _draw_corals() -> void:
	var inner := _tank_inner()
	var sand_top := inner.end.y - SAND_HEIGHT
	var coral_index := 0
	for item in _scape_items("corals"):
		var quantity := int(item.get("quantity", 0))
		var kind := str(item.get("type", "zoanthids"))
		var health: float = clamp(float(item.get("health", 0.82)), 0.0, 1.0)
		for n in range(quantity):
			var seed := coral_index + n + kind.length() * 3
			var pos := Vector2(
				inner.position.x + inner.size.x * (0.36 + fposmod(float(seed) * 0.117, 0.36)),
				sand_top - 8.0 + fposmod(float(seed) * 13.0, 28.0)
			)
			pos = _object_pos(item, pos)
			var draw_size := Vector2(74, 58) if kind != "torch_coral" else Vector2(88, 92)
			var tint := Color.WHITE.lerp(Color("#b79b82"), 1.0 - health)
			if not _draw_scape_sprite(kind, pos, draw_size, seed % 2 == 0, tint):
				_draw_coral_fallback(kind, pos, seed, health)
		coral_index += quantity

func _draw_coral_fallback(kind: String, pos: Vector2, seed: int, health: float) -> void:
	var base := Color("#69cf80") if kind == "green_star_polyps" else Color("#d58adc")
	if kind == "mushroom_coral":
		base = Color("#b86aa8")
	elif kind == "torch_coral":
		base = Color("#e5c978")
	base = base.lerp(Color("#a07862"), 1.0 - health)
	if kind == "torch_coral":
		for arm in range(7):
			var angle := -PI * 0.86 + float(arm) * PI * 0.26
			var sway := sin(Time.get_ticks_msec() / 850.0 + seed + arm) * 5.0
			var tip := pos + Vector2(cos(angle) * 24.0 + sway, -28.0 + sin(angle) * 22.0)
			draw_line(pos, tip, base, 4.0, true)
			draw_circle(tip, 5.0, base.lightened(0.14))
	else:
		for polyp in range(9):
			var offset := Vector2(cos(polyp * TAU / 9.0) * (10.0 + polyp % 3 * 4.0), sin(polyp * TAU / 9.0) * 8.0)
			draw_circle(pos + offset, 7.0, base.darkened(float(polyp % 2) * 0.05))
			draw_circle(pos + offset, 2.0, base.lightened(0.25))

func _draw_scape_sprite(item_type: String, pos: Vector2, draw_size: Vector2, flip: bool = false, modulate: Color = Color.WHITE) -> bool:
	if not scape_textures.has(item_type):
		return false
	var texture: Texture2D = scape_textures[item_type]
	draw_set_transform(pos, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	draw_texture_rect(texture, Rect2(-draw_size * 0.5, draw_size), false, modulate)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true

func _draw_rock(pos: Vector2, radius: float, color: Color, seed: int) -> void:
	var points := PackedVector2Array()
	for p in range(10):
		var angle := TAU * float(p) / 10.0
		var wobble := 0.78 + fposmod(sin(seed * 3.7 + p * 1.9), 1.0) * 0.32
		points.push_back(pos + Vector2(cos(angle), sin(angle)) * radius * wobble)
	var colors := PackedColorArray()
	for p in range(points.size()):
		colors.push_back(color.darkened(float(p % 3) * 0.025))
	draw_polygon(points, colors)
	draw_circle(pos + Vector2(-radius * 0.28, -radius * 0.22), radius * 0.2, Color(1, 1, 1, 0.06))

func _draw_driftwood(root: Vector2, branch_count: int, seed: int) -> void:
	for branch in range(branch_count):
		var end := root + Vector2(-150.0 + branch * 54.0 + seed * 12.0, -62.0 - float((branch + seed) % 2) * 42.0)
		var bend := root.lerp(end, 0.46) + Vector2(18.0 * sin(branch + seed), -20.0)
		var curve := Curve2D.new()
		curve.add_point(root)
		curve.add_point(bend)
		curve.add_point(end)
		var baked := curve.get_baked_points()
		if baked.size() > 1:
			draw_polyline(baked, Color("#5b3d2b"), max(4.0, 10.0 - branch), true)
			draw_polyline(baked, Color(0.18, 0.10, 0.06, 0.42), 3.0, true)

func _draw_plants() -> void:
	var inner := _tank_inner()
	var sand_top := inner.end.y - SAND_HEIGHT
	var fallback_done := false
	for item in _scape_items("plants"):
		var kind := str(item.get("type", "java_fern"))
		var quantity := int(item.get("quantity", 0))
		for n in range(quantity):
			var seed := n + quantity * kind.length()
			match kind:
				"dwarf_hairgrass":
					var pos := Vector2(inner.position.x + fposmod(seed * 31.0, inner.size.x), sand_top + 17.0 + fposmod(seed * 17.0, 34.0))
					pos = _object_pos(item, pos)
					if not _draw_scape_sprite(kind, pos, Vector2(86, 86), seed % 2 == 0):
						_draw_carpet_patch(seed, inner, sand_top)
				"vallisneria":
					var pos := Vector2(inner.position.x + 42.0 + fposmod(seed * 73.0, inner.size.x - 84.0), sand_top - 38.0)
					pos = _object_pos(item, pos)
					if not _draw_scape_sprite(kind, pos, Vector2(86, 132), seed % 2 == 0):
						_draw_vallisneria(seed, inner, sand_top)
				"java_fern":
					var pos := Vector2(inner.position.x + 48.0 + fposmod(seed * 59.0, inner.size.x - 96.0), sand_top - 18.0)
					pos = _object_pos(item, pos)
					if not _draw_scape_sprite(kind, pos, Vector2(78, 78), seed % 2 == 0):
						_draw_rosette(seed, inner, sand_top, Color("#4f9c5c"), 42.0)
				"anubias":
					var pos := Vector2(inner.position.x + 48.0 + fposmod(seed * 59.0, inner.size.x - 96.0), sand_top - 12.0)
					pos = _object_pos(item, pos)
					if not _draw_scape_sprite(kind, pos, Vector2(66, 66), seed % 2 == 0):
						_draw_rosette(seed, inner, sand_top, Color("#3f8758"), 30.0)
				"red_root_floaters":
					var pos := Vector2(inner.position.x + 44.0 + fposmod(seed * 67.0, inner.size.x - 88.0), inner.position.y + 46.0 + fposmod(seed * 11.0, 25.0))
					pos = _object_pos(item, pos)
					if not _draw_scape_sprite(kind, pos, Vector2(70, 70), seed % 2 == 0):
						_draw_floaters(seed, inner)
				"halimeda_macroalgae":
					var pos := _object_pos(item, Vector2(inner.position.x + 48.0 + fposmod(seed * 59.0, inner.size.x - 96.0), sand_top - 16.0))
					if not _draw_scape_sprite(kind, pos, Vector2(76, 76), seed % 2 == 0):
						_draw_rosette(seed, inner, sand_top, Color("#78ba70"), 34.0)
				_:
					_draw_rosette(seed, inner, sand_top, Color("#5ca86c"), 34.0)
		fallback_done = true
	if not fallback_done:
		for i in range(20):
			_draw_carpet_patch(i, inner, sand_top)

func _draw_carpet_patch(seed: int, inner: Rect2, sand_top: float) -> void:
	var x := inner.position.x + fposmod(seed * 31.0, inner.size.x)
	var y := sand_top + 10.0 + fposmod(seed * 17.0, 46.0)
	var leaf := Color("#5fbf73") if seed % 2 == 0 else Color("#7ad089")
	_draw_leaf(Vector2(x, y), 12.0, 5.0, leaf)

func _draw_vallisneria(seed: int, inner: Rect2, sand_top: float) -> void:
	var base_x := inner.position.x + 34.0 + fposmod(seed * 73.0, inner.size.x - 68.0)
	var height := 72.0 + float((seed * 29) % 96)
	var base := Vector2(base_x, sand_top + 8.0)
	var sway := sin(Time.get_ticks_msec() / 1200.0 + seed) * 10.0
	for blade in range(4):
		var offset := float(blade - 1) * 4.0
		var tip := base + Vector2(offset + sway * (0.45 + blade * 0.08), -height + blade * 13.0)
		draw_line(base + Vector2(offset, 0), tip, Color("#6cbd72"), 3.0, true)

func _draw_rosette(seed: int, inner: Rect2, sand_top: float, color: Color, height: float) -> void:
	var base := Vector2(
		inner.position.x + 48.0 + fposmod(seed * 59.0, inner.size.x - 96.0),
		sand_top + 8.0 - fposmod(seed * 13.0, 26.0)
	)
	for leaf_index in range(7):
		var angle := -PI * 0.95 + float(leaf_index) * PI * 0.32
		var tip := base + Vector2(cos(angle) * height * 0.58, sin(angle) * height)
		draw_line(base, tip, color.darkened(0.08), 3.0, true)
		_draw_leaf(tip, 16.0, 7.0, color.lightened(float(leaf_index % 2) * 0.05))

func _draw_floaters(seed: int, inner: Rect2) -> void:
	var base := Vector2(
		inner.position.x + 28.0 + fposmod(seed * 67.0, inner.size.x - 56.0),
		inner.position.y + 26.0 + fposmod(seed * 11.0, 28.0)
	)
	for leaf_index in range(4):
		var pos := base + Vector2(cos(leaf_index * TAU / 4.0) * 9.0, sin(leaf_index * TAU / 4.0) * 4.0)
		_draw_leaf(pos, 12.0, 7.0, Color("#76b86a"))
		draw_line(pos, pos + Vector2(3.0, 14.0 + leaf_index * 3.0), Color("#c26163"), 1.1, true)

func _draw_bubbles() -> void:
	var inner := _tank_inner()
	for i in range(18):
		var speed := 16.0 + float(i % 6) * 5.0
		var x := inner.position.x + 42.0 + fposmod(i * 91.0, inner.size.x - 84.0)
		var y := inner.end.y - SAND_HEIGHT - fposmod(Time.get_ticks_msec() / 1000.0 * speed + i * 39.0, inner.size.y - 80.0)
		var radius := 2.2 + float(i % 4)
		draw_circle(Vector2(x, y), radius, Color(0.83, 0.98, 1.0, 0.12), false, 1.3, true)

func _draw_front_glass() -> void:
	var inner := _tank_inner()
	draw_line(inner.position + Vector2(24, 14), inner.position + Vector2(inner.size.x * 0.46, 14), Color(1, 1, 1, 0.12), 2.0, true)
	draw_line(inner.position + Vector2(inner.size.x - 118, 30), inner.position + Vector2(inner.size.x - 34, 30), Color(1, 1, 1, 0.10), 2.0, true)

func _draw_animals() -> void:
	for animal in state.get("animals", []):
		if not animal.get("alive", true):
			continue
		var id: String = str(animal.get("id", ""))
		if not animal_visuals.has(id):
			continue
		var visual: Dictionary = animal_visuals[id]
		var spec = species.get(animal.get("species_id", ""), {})
		var pos: Vector2 = visual.get("pos", Vector2.ZERO)
		var facing := float(visual.get("facing", 1.0))
		var stress := float(animal.get("acute_stress", 0.0))
		var health := float(animal.get("health", 1.0))
		var tint := Color(spec.get("color", "#cccccc")).lerp(Color("#d8c8a0"), clamp(stress * 0.35 + (1.0 - health) * 0.4, 0.0, 0.55))
		var accent := Color(spec.get("accent", "#ffffff"))
		if _draw_fish_sprite(str(animal.get("species_id", "")), pos, facing, stress, health):
			continue
		var visual_family := str(spec.get("visual_family", animal.get("species_id", "")))
		match visual_family:
			"cherry_shrimp":
				_draw_shrimp(pos, facing, tint, accent, visual)
			"betta_splendens":
				_draw_betta(pos, facing, tint, accent, visual)
			"zebra_danio":
				_draw_danio(pos, facing, tint, accent, visual)
			"peppered_cory":
				_draw_cory(pos, facing, tint, accent, visual)
			"rasbora":
				_draw_rasbora(pos, facing, tint, accent, visual)
			"guppy":
				_draw_guppy(pos, facing, tint, accent, visual)
			"gourami":
				_draw_gourami(pos, facing, tint, accent, visual)
			"loach":
				_draw_loach(pos, facing, tint, accent, visual)
			_:
				_draw_tetra(pos, facing, tint, accent, visual)

func _draw_fish_sprite(species_id: String, pos: Vector2, facing: float, stress: float, health: float) -> bool:
	if not fish_textures.has(species_id):
		return false
	var texture: Texture2D = fish_textures[species_id]
	var draw_size := _fish_sprite_size(species_id)
	var warmth: float = clamp(stress * 0.18 + (1.0 - health) * 0.22, 0.0, 0.35)
	var modulate := Color(1.0, 1.0 - warmth * 0.18, 1.0 - warmth * 0.28, 1.0)
	draw_set_transform(pos, 0.0, Vector2(1.0 if facing >= 0 else -1.0, 1.0))
	draw_texture_rect(texture, Rect2(-draw_size * 0.5, draw_size), false, modulate)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true

func _fish_sprite_size(species_id: String) -> Vector2:
	match species_id:
		"cherry_shrimp":
			return Vector2(52, 30)
		"kuhli_loach":
			return Vector2(92, 46)
		"betta_splendens":
			return Vector2(74, 42)
		"peppered_cory":
			return Vector2(72, 40)
		"honey_gourami":
			return Vector2(68, 38)
		"fancy_guppy":
			return Vector2(58, 34)
		"zebra_danio":
			return Vector2(64, 32)
		"harlequin_rasbora":
			return Vector2(62, 34)
		_:
			var spec: Dictionary = species.get(species_id, {})
			var adult_cm := float(spec.get("adult_cm", 4.0))
			return Vector2(clamp(adult_cm * 9.0, 48.0, 96.0), clamp(adult_cm * 4.8, 28.0, 52.0))

func _fish_points(pos: Vector2, facing: float, length: float, height: float) -> PackedVector2Array:
	return PackedVector2Array([
		pos + Vector2(-length * 0.46 * facing, 0),
		pos + Vector2(-length * 0.18 * facing, -height * 0.48),
		pos + Vector2(length * 0.22 * facing, -height * 0.42),
		pos + Vector2(length * 0.48 * facing, 0),
		pos + Vector2(length * 0.22 * facing, height * 0.42),
		pos + Vector2(-length * 0.18 * facing, height * 0.48)
	])

func _draw_eye(pos: Vector2, facing: float, length: float, height: float) -> void:
	var eye := pos + Vector2(length * 0.31 * facing, -height * 0.12)
	draw_circle(eye, max(1.5, height * 0.095), Color("#f7fbf8"))
	draw_circle(eye + Vector2(0.8 * facing, 0.3), max(0.8, height * 0.045), Color("#10181b"))

func _draw_leaf(pos: Vector2, width: float, height: float, color: Color) -> void:
	draw_polygon(PackedVector2Array([
		pos + Vector2(-width * 0.5, 0),
		pos + Vector2(-width * 0.22, -height * 0.5),
		pos + Vector2(width * 0.34, -height * 0.36),
		pos + Vector2(width * 0.5, 0),
		pos + Vector2(width * 0.2, height * 0.48),
		pos + Vector2(-width * 0.3, height * 0.36)
	]), PackedColorArray([color, color.lightened(0.04), color, color.darkened(0.03), color, color.lightened(0.02)]))

func _draw_tetra(pos: Vector2, facing: float, color: Color, accent: Color, visual: Dictionary) -> void:
	var length := 46.0
	var height := 17.0
	draw_polygon(PackedVector2Array([
		pos + Vector2(-length * 0.48 * facing, 0),
		pos + Vector2(-length * 0.72 * facing, -height * 0.52),
		pos + Vector2(-length * 0.66 * facing, height * 0.48)
	]), PackedColorArray([accent, accent, accent]))
	draw_polygon(_fish_points(pos, facing, length, height), PackedColorArray([color, color.lightened(0.06), color, color.darkened(0.05), color, color.lightened(0.04)]))
	draw_line(pos + Vector2(-16 * facing, -2), pos + Vector2(16 * facing, -2), Color("#8be8ff"), 3.0, true)
	draw_line(pos + Vector2(-14 * facing, 4), pos + Vector2(6 * facing, 4), accent, 3.0, true)
	_draw_eye(pos, facing, length, height)

func _draw_rasbora(pos: Vector2, facing: float, color: Color, accent: Color, visual: Dictionary) -> void:
	var length := 50.0
	var height := 18.0
	draw_polygon(PackedVector2Array([
		pos + Vector2(-length * 0.47 * facing, 0),
		pos + Vector2(-length * 0.68 * facing, -height * 0.45),
		pos + Vector2(-length * 0.66 * facing, height * 0.44)
	]), PackedColorArray([color.darkened(0.12), color.darkened(0.08), color.darkened(0.12)]))
	draw_polygon(_fish_points(pos, facing, length, height), PackedColorArray([color.darkened(0.04), color, color.lightened(0.1), color.lightened(0.05), color, color.darkened(0.04)]))
	draw_polygon(PackedVector2Array([
		pos + Vector2(-10 * facing, -6),
		pos + Vector2(16 * facing, -3),
		pos + Vector2(7 * facing, 8),
		pos + Vector2(-15 * facing, 4)
	]), PackedColorArray([accent, accent, accent, accent]))
	_draw_eye(pos, facing, length, height)

func _draw_guppy(pos: Vector2, facing: float, color: Color, accent: Color, visual: Dictionary) -> void:
	var phase := float(visual.get("phase", 0.0))
	var length := 43.0
	var height := 15.0
	var tail_fan := 16.0 + sin(phase * 2.3) * 2.0
	draw_polygon(PackedVector2Array([
		pos + Vector2(-length * 0.36 * facing, 0),
		pos + Vector2((-length * 0.36 - tail_fan) * facing, -height * 0.95),
		pos + Vector2((-length * 0.62 - tail_fan * 0.45) * facing, 0),
		pos + Vector2((-length * 0.36 - tail_fan) * facing, height * 0.95)
	]), PackedColorArray([accent, accent.lightened(0.16), color.lightened(0.08), accent]))
	draw_polygon(_fish_points(pos, facing, length, height), PackedColorArray([color, color.lightened(0.12), color.lightened(0.05), color, color.darkened(0.05), color]))
	draw_circle(pos + Vector2(-3 * facing, -1), 3.0, accent.lightened(0.1))
	draw_circle(pos + Vector2(7 * facing, 3), 2.0, accent.darkened(0.06))
	_draw_eye(pos, facing, length, height)

func _draw_gourami(pos: Vector2, facing: float, color: Color, accent: Color, visual: Dictionary) -> void:
	var phase := float(visual.get("phase", 0.0))
	var length := 52.0
	var height := 25.0
	draw_polygon(PackedVector2Array([
		pos + Vector2(-length * 0.45 * facing, 0),
		pos + Vector2(-length * 0.68 * facing, -height * 0.38),
		pos + Vector2(-length * 0.68 * facing, height * 0.38)
	]), PackedColorArray([accent, accent.lightened(0.08), accent]))
	draw_polygon(_fish_points(pos, facing, length, height), PackedColorArray([color.darkened(0.04), color, color.lightened(0.08), color.lightened(0.05), color, color.darkened(0.06)]))
	draw_arc(pos + Vector2(-3 * facing, -height * 0.12), 17.0, PI * 1.07, PI * 1.88, 20, accent.lightened(0.04), 2.5, true)
	draw_line(pos + Vector2(5 * facing, height * 0.48), pos + Vector2(9 * facing + sin(phase) * 6.0, height * 1.35), accent, 1.5, true)
	draw_line(pos + Vector2(10 * facing, height * 0.44), pos + Vector2(18 * facing + cos(phase) * 5.0, height * 1.18), accent, 1.5, true)
	_draw_eye(pos, facing, length, height)

func _draw_betta(pos: Vector2, facing: float, color: Color, accent: Color, visual: Dictionary) -> void:
	var phase := float(visual.get("phase", 0.0))
	var length := 56.0
	var height := 22.0
	var tail_wave := sin(phase * 2.0) * 5.0
	draw_polygon(PackedVector2Array([
		pos + Vector2(-length * 0.37 * facing, 0),
		pos + Vector2(-length * 0.86 * facing, -height * 0.92 + tail_wave),
		pos + Vector2(-length * 0.76 * facing, 0),
		pos + Vector2(-length * 0.86 * facing, height * 0.94 + tail_wave)
	]), PackedColorArray([accent, accent.lightened(0.12), accent.darkened(0.04), accent]))
	draw_polygon(_fish_points(pos, facing, length, height), PackedColorArray([color.darkened(0.06), color, color.lightened(0.08), color.lightened(0.05), color, color.darkened(0.04)]))
	draw_arc(pos + Vector2(-5 * facing, height * 0.28), 18.0, PI * 0.08, PI * 0.92, 20, accent.lightened(0.1), 3.0, true)
	draw_arc(pos + Vector2(-4 * facing, -height * 0.25), 16.0, PI * 1.1, PI * 1.86, 20, accent.lightened(0.08), 2.6, true)
	_draw_eye(pos, facing, length, height)

func _draw_danio(pos: Vector2, facing: float, color: Color, accent: Color, visual: Dictionary) -> void:
	var length := 54.0
	var height := 16.0
	draw_polygon(PackedVector2Array([
		pos + Vector2(-length * 0.46 * facing, 0),
		pos + Vector2(-length * 0.68 * facing, -height * 0.42),
		pos + Vector2(-length * 0.68 * facing, height * 0.42)
	]), PackedColorArray([accent, accent, accent]))
	draw_polygon(_fish_points(pos, facing, length, height), PackedColorArray([color, color.lightened(0.1), color, color, color.darkened(0.04), color]))
	for stripe in range(4):
		var y := -5.5 + stripe * 3.4
		draw_line(pos + Vector2(-17 * facing, y), pos + Vector2(20 * facing, y + 1.2), accent, 1.8, true)
	_draw_eye(pos, facing, length, height)

func _draw_cory(pos: Vector2, facing: float, color: Color, accent: Color, visual: Dictionary) -> void:
	var length := 58.0
	var height := 20.0
	draw_polygon(PackedVector2Array([
		pos + Vector2(-length * 0.45 * facing, 1),
		pos + Vector2(-length * 0.64 * facing, -height * 0.25),
		pos + Vector2(-length * 0.62 * facing, height * 0.34)
	]), PackedColorArray([accent, accent, accent]))
	draw_polygon(_fish_points(pos + Vector2(0, 5), facing, length, height), PackedColorArray([color.darkened(0.08), color, color.lightened(0.08), color, color.darkened(0.12), color.darkened(0.05)]))
	for spot in range(7):
		var offset := Vector2((-18.0 + spot * 6.0) * facing, -2.0 + sin(spot) * 5.0)
		draw_circle(pos + offset, 2.0, accent.darkened(0.1))
	draw_line(pos + Vector2(length * 0.38 * facing, 7), pos + Vector2(length * 0.58 * facing, 13), accent, 1.4, true)
	draw_line(pos + Vector2(length * 0.38 * facing, 8), pos + Vector2(length * 0.58 * facing, 3), accent, 1.4, true)
	_draw_eye(pos + Vector2(0, 4), facing, length, height)

func _draw_loach(pos: Vector2, facing: float, color: Color, accent: Color, visual: Dictionary) -> void:
	var phase := float(visual.get("phase", 0.0))
	var points := PackedVector2Array()
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in range(12):
		var ratio := float(i) / 11.0
		var x := (-42.0 + ratio * 84.0) * facing
		var wave := sin(phase * 2.0 + ratio * TAU * 1.4) * 5.5
		var thickness := 5.5 + sin(ratio * PI) * 5.0
		top.push_back(pos + Vector2(x, wave - thickness))
		bottom.push_back(pos + Vector2(x, wave + thickness))
	points.append_array(top)
	for i in range(bottom.size() - 1, -1, -1):
		points.push_back(bottom[i])
	var colors := PackedColorArray()
	for i in range(points.size()):
		colors.push_back(color)
	draw_polygon(points, colors)
	for band in range(6):
		var ratio := float(band) / 5.0
		var x := (-34.0 + ratio * 68.0) * facing
		draw_line(pos + Vector2(x, -8), pos + Vector2(x - 4 * facing, 8), accent, 4.0, true)
	_draw_eye(pos + Vector2(30 * facing, sin(phase) * 2.0), facing, 46.0, 15.0)

func _draw_shrimp(pos: Vector2, facing: float, color: Color, accent: Color, visual: Dictionary) -> void:
	var phase := float(visual.get("phase", 0.0))
	draw_arc(pos, 18.0, PI * 1.05, PI * 1.95, 18, color, 5.0, true)
	draw_circle(pos + Vector2(15 * facing, -5), 5.5, color.lightened(0.08))
	draw_line(pos + Vector2(18 * facing, -7), pos + Vector2(30 * facing, -14 + sin(phase) * 2), accent, 1.2, true)
	draw_line(pos + Vector2(18 * facing, -6), pos + Vector2(31 * facing, -7), accent, 1.2, true)
	for leg in range(5):
		var x := (-8.0 + leg * 4.0) * facing
		draw_line(pos + Vector2(x, 4), pos + Vector2(x + 3 * facing, 12), color.darkened(0.08), 1.4, true)
	draw_circle(pos + Vector2(18 * facing, -8), 1.4, Color("#151a1d"))

func _refresh_ui() -> void:
	var summary = state.get("summary", {})
	var water = state.get("water", {})
	var status = str(summary.get("status", "stable")).capitalize()
	var living := int(summary.get("living_animals", 0))
	var stressed := int(summary.get("stressed_animals", 0))
	status_label.text = "%s - %d animals - %d stressed" % [status, living, stressed]
	summary_label.text = "The aquarium keeps living in the background. Open this window to feed, change water, and check what the tank is telling you."
	var aquarium = state.get("aquarium", {})
	if scape_label:
		scape_label.text = "Plants affect nitrate, oxygen, algae, cover, and maintenance. Cover %.0f%% - algae control %.0f%% - upkeep %.0f%%" % [
			float(aquarium.get("plant_cover", 0.0)) * 100.0,
			float(aquarium.get("algae_control", 0.0)) * 100.0,
			float(aquarium.get("maintenance_load", 0.0)) * 100.0
		]
	for key in water_labels.keys():
		water_labels[key].text = _format_water(key, float(water.get(key, 0.0)))
	animal_list.clear()
	animal_ids.clear()
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
		animal_ids.append(str(animal.get("id", "")))
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
			return "Oxygen: %.1f mg/L" % value
		"ammonia_mg_l":
			return "Ammonia: %.3f mg/L" % value
		"nitrite_mg_l":
			return "Nitrite: %.3f mg/L" % value
		"nitrate_mg_l":
			return "Nitrate: %.1f mg/L" % value
	return "%s: %.2f" % [key, value]
