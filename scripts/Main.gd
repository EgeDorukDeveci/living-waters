extends Control

const PANEL_WIDTH := 388.0
const EDGE := 28.0
const TOP_BAR := 76.0
const SAND_HEIGHT := 74.0
const COMMAND_FEED := {"action": "feed", "amount": 0.42}
const COMMAND_WATER_CHANGE := {"action": "water_change", "fraction": 0.25}
const COMMAND_SERVICE_FILTER := {"action": "service_filter", "replace_carbon": true}
const COMMAND_WEEKLY_MAINTENANCE := {"action": "weekly_maintenance"}
const COMMAND_REMOVE_FOOD := {"action": "remove_uneaten_food"}
const COMMAND_SCRAPE_ALGAE := {"action": "scrape_algae"}
const COMMAND_TRIM_PLANTS := {"action": "trim_plants"}
const COMMAND_TOP_OFF := {"action": "top_off"}
const COMMAND_EMPTY_SKIMMER := {"action": "empty_skimmer_cup"}
const COMMAND_DOSE_MINERALS := {"action": "dose_minerals", "strength": 1.0}
const COMMAND_DOSE_AMMONIA := {"action": "dose_ammonia", "amount": 1.0}
const COMMAND_TEST_WATER := {"action": "test_water"}
const COMMAND_TREAT_OUTBREAK := {"action": "treat_outbreak", "strength": 0.55, "days": 5.0}
const FOOD_OPTIONS := [
	{"id": "community_flake", "label": "Community flake", "hint": "surface/midwater, balanced, moderate clouding"},
	{"id": "micro_pellet", "label": "Micro pellet", "hint": "small fish, cleaner water, slow sink"},
	{"id": "sinking_wafer", "label": "Sinking wafer", "hint": "bottom fish, heavier leftovers"},
	{"id": "frozen_invertebrates", "label": "Frozen invertebrates", "hint": "high protein, rich, dirtier water"},
	{"id": "algae_wafer", "label": "Algae wafer", "hint": "grazers and shrimp, sinks fast"},
	{"id": "reef_plankton", "label": "Reef plankton", "hint": "marine fish/corals, nutrient rich"}
]
const PLANT_SCAPE_TYPES := [
	"dwarf_hairgrass", "java_fern", "anubias", "vallisneria", "red_root_floaters",
	"amazon_sword", "cryptocoryne_wendtii", "java_moss", "hornwort",
	"halimeda_macroalgae", "turtle_grass"
]
const CORAL_SCAPE_TYPES := ["zoanthids", "mushroom_coral", "green_star_polyps", "torch_coral", "pulsing_xenia", "kenya_tree_coral"]
const DISTURBING_ACTIONS := [
	"water_change", "weekly_maintenance", "remove_uneaten_food", "scrape_algae", "trim_plants",
	"service_filter", "set_substrate", "add_animal", "remove_animal", "place_scape_item",
	"move_scape_item", "remove_scape_item", "reset_scape", "clear_scape", "quarantine_animal", "treat_outbreak"
]

var root_dir: String
var state_path: String
var index_path: String
var command_path: String
var commands_dir: String
var species_path: String
var state: Dictionary = {}
var species: Dictionary = {}
var aquarium_index: Dictionary = {}
var animal_visuals: Dictionary = {}
var fish_textures: Dictionary = {}
var scape_textures: Dictionary = {}
var journal_sketch_textures: Dictionary = {}
var opening_background_texture: Texture2D
var time_accum := 0.0
var opening_screen := true
var opening_cards: Array[Dictionary] = []
var opening_enter_rect := Rect2()

var side_panel: PanelContainer
var panel: VBoxContainer
var keeper_tabs: TabContainer
var animal_list: ItemList
var tank_name_edit: LineEdit
var tank_litres_spin: SpinBox
var tank_system_select: OptionButton
var substrate_select: OptionButton
var substrate_depth_spin: SpinBox
var filter_flow_spin: SpinBox
var heater_target_spin: SpinBox
var light_hours_spin: SpinBox
var air_output_spin: SpinBox
var replacement_temp_spin: SpinBox
var replacement_ph_spin: SpinBox
var replacement_gh_spin: SpinBox
var disturb_substrate_check: CheckBox
var species_select: OptionButton
var food_select: OptionButton
var status_label: Label
var summary_label: Label
var research_label: Label
var notebook_right_label: Label
var notebook_left_page_label: Label
var notebook_right_page_label: Label
var notebook_left_sketch: TextureRect
var notebook_right_sketch: TextureRect
var notebook_left_page: PanelContainer
var notebook_right_page: PanelContainer
var notebook_prev_button: Button
var notebook_next_button: Button
var notebook_index_select: OptionButton
var notebook_panel: PanelContainer
var notebook_button: Button
var aquarium_shelf_button: Button
var scape_label: Label
var scape_selection_label: Label
var scape_scale_spin: SpinBox
var scape_rotation_spin: SpinBox
var scape_layer_select: OptionButton
var scape_flip_check: CheckBox
var tool_label: Label
var title_label: Label
var animal_ids: Array = []
var selected_animal_id := ""
var selected_scape_tool: Dictionary = {}
var selected_scape_object_id := ""
var selected_animal_tool: Dictionary = {}
var action_effects: Array[Dictionary] = []
var last_command_note := ""
var last_command_until := 0.0
var synced_food_type := ""
var notebook_open := false
var notebook_amount := 0.0
var notebook_pages: Array = []
var notebook_page_titles: Array[String] = []
var notebook_page_sketches: Array[String] = []
var notebook_page_index := 0
var notebook_turn_amount := 0.0
var notebook_turn_direction := 1

func _ready() -> void:
	root_dir = _project_root()
	state_path = root_dir.path_join("runtime").path_join("aquarium_state.json")
	index_path = root_dir.path_join("runtime").path_join("aquariums").path_join("index.json")
	command_path = root_dir.path_join("runtime").path_join("command.json")
	commands_dir = root_dir.path_join("runtime").path_join("commands")
	species_path = root_dir.path_join("data").path_join("species").path_join("freshwater_v1.json")
	species = _load_species(species_path)
	_load_sprite_assets()
	_build_ui()
	_load_state()
	queue_redraw()

func _process(delta: float) -> void:
	time_accum += delta
	_animate_animals(delta)
	_update_action_effects(delta)
	_update_notebook_animation(delta)
	if time_accum > 1.0:
		time_accum = 0.0
		_load_state()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_ui()

func _set_opening_mode(enabled: bool) -> void:
	opening_screen = enabled
	if title_label:
		title_label.visible = not enabled
	if status_label:
		status_label.visible = not enabled
	if aquarium_shelf_button:
		aquarium_shelf_button.visible = not enabled
	if side_panel:
		side_panel.visible = not enabled
	if notebook_panel:
		notebook_panel.visible = not enabled and (notebook_amount > 0.02 or notebook_open)
	queue_redraw()

func _handle_opening_click(mouse: Vector2) -> void:
	for card in opening_cards:
		var rect: Rect2 = card.get("rect", Rect2())
		if rect.has_point(mouse):
			var aquarium_id := str(card.get("id", ""))
			if aquarium_id != "":
				_write_command({"action": "select_aquarium", "aquarium_id": aquarium_id})
				_set_opening_mode(false)
				return
	if opening_enter_rect.has_point(mouse):
		_set_opening_mode(false)

func _gui_input(event: InputEvent) -> void:
	if opening_screen:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_opening_click(event.position)
		elif event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_SPACE, KEY_ESCAPE]:
			_set_opening_mode(false)
		return
	if notebook_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_toggle_notebook(false)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_clear_scape_editor()
			return
		if event.keycode in [KEY_DELETE, KEY_BACKSPACE] and selected_scape_object_id != "":
			_remove_selected_scape()
			return
		if event.ctrl_pressed and event.keycode == KEY_D and selected_scape_object_id != "":
			_duplicate_selected_scape()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse: Vector2 = event.position
		var inner := _tank_inner()
		if not inner.has_point(mouse):
			return
		var normalized := Vector2(
			clamp((mouse.x - inner.position.x) / inner.size.x, 0.0, 1.0),
			clamp((mouse.y - inner.position.y) / inner.size.y, 0.0, 1.0)
		)
		if not selected_animal_tool.is_empty():
			if not _valid_release_point(normalized):
				if tool_label:
					tool_label.text = "Release inside open water, away from the rim and substrate."
				return
			var species_id := str(selected_animal_tool.get("species_id", ""))
			var minutes := int(selected_animal_tool.get("acclimation_minutes", 30))
			_write_command({"action": "add_animal", "species_id": species_id, "acclimation_minutes": minutes, "x": normalized.x, "y": normalized.y})
			if tool_label:
				tool_label.text = "Released into the aquarium. Watch behavior and water tests over time."
			selected_animal_tool = {}
			return
		var hit := _hit_scape_object(mouse)
		if selected_scape_tool.is_empty() and hit != "":
			_select_scape_object(hit)
			return
		if selected_scape_object_id != "":
			if _client_position_valid("", "", normalized):
				var move_command := _scape_object_action_command("move_scape_item", selected_scape_object_id)
				move_command["x"] = normalized.x
				move_command["y"] = normalized.y
				var move_transform: Dictionary = _scape_transform_values()
				for key in move_transform:
					move_command[key] = move_transform[key]
				_write_command(move_command)
				if tool_label:
					tool_label.text = "Relocated the selected piece with its current object-editor settings."
			return
		if selected_scape_tool.is_empty():
			return
		var category := str(selected_scape_tool.get("category", ""))
		var item_type := str(selected_scape_tool.get("type", ""))
		if not _client_position_valid(category, item_type, normalized):
			return
		var place_command := {"action": "place_scape_item", "category": category, "type": item_type, "x": normalized.x, "y": normalized.y}
		var place_transform: Dictionary = _scape_transform_values()
		for key in place_transform:
			place_command[key] = place_transform[key]
		_write_command(place_command)
		selected_scape_tool = {}
		if tool_label:
			tool_label.text = "Placed %s. Select it on the canvas to keep shaping the composition." % str(place_command.get("type", "piece")).replace("_", " ")

func _client_position_valid(category: String, item_type: String, normalized: Vector2, quiet: bool = false) -> bool:
	if category == "":
		return true
	if category == "plants" and item_type == "red_root_floaters":
		if normalized.y > 0.22:
			if tool_label and not quiet:
				tool_label.text = "Floaters need the surface, not the substrate."
			return false
		return true
	if category == "plants" and item_type == "hornwort":
		if normalized.y > 0.25 and normalized.y < 0.70:
			if tool_label and not quiet:
				tool_label.text = "Hornwort must float near the surface or be planted into substrate."
			return false
		return true
	if category == "plants" and normalized.y < 0.70:
		if tool_label and not quiet:
			tool_label.text = "Rooted plants cannot be placed in open water."
		return false
	if category in ["rocks", "wood", "corals"] and normalized.y < 0.52:
		if tool_label and not quiet:
			tool_label.text = "That item needs a surface, not open water."
		return false
	return true

func _valid_release_point(normalized: Vector2) -> bool:
	return normalized.y > 0.10 and normalized.y < 0.86

func _add_action_effect(kind: String, command: Dictionary = {}) -> void:
	var effect := command.duplicate(true)
	effect["kind"] = kind
	effect["age"] = 0.0
	effect["duration"] = _effect_duration(kind)
	effect["seed"] = Time.get_ticks_msec() % 1000
	action_effects.append(effect)

func _effect_duration(kind: String) -> float:
	match kind:
		"feed":
			return 4.2
		"water_change":
			return 4.6
		"weekly_maintenance":
			return 5.0
		"remove_uneaten_food", "scrape_algae", "trim_plants":
			return 3.6
		"top_off", "empty_skimmer_cup":
			return 3.3
		"service_filter":
			return 4.0
		"test_water":
			return 3.4
		"dose_ammonia", "dose_minerals":
			return 3.5
		"set_substrate":
			return 4.0
		"add_animal", "remove_animal":
			return 4.0
		"place_scape_item", "move_scape_item", "duplicate_scape_item", "remove_scape_item":
			return 3.5
		"reset_scape", "clear_scape":
			return 3.7
		"set_equipment":
			return 3.2
		"switch_system":
			return 4.2
		"create_aquarium", "select_aquarium":
			return 2.6
		"quarantine_animal":
			return 3.8
		"treat_outbreak":
			return 4.0
		"install_safeguards":
			return 4.2
	return 1.6

func _update_action_effects(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for effect in action_effects:
		effect["age"] = float(effect.get("age", 0.0)) + delta
		if float(effect["age"]) < float(effect.get("duration", 1.0)):
			alive.append(effect)
	action_effects = alive

func _draw() -> void:
	if opening_screen:
		_draw_opening_screen()
		return
	_draw_room()
	_draw_aquarium()
	_draw_hardscape()
	_draw_custom_scape_objects(0)
	_draw_corals()
	_draw_custom_scape_objects(1)
	_draw_plants()
	_draw_custom_scape_objects(2)
	_draw_bubbles()
	_draw_animals()
	_draw_action_effects()
	_draw_scape_editor_overlay()
	_draw_front_glass()

func _draw_opening_screen() -> void:
	_draw_opening_shelf()

func _draw_opening_backdrop() -> void:
	if opening_background_texture:
		draw_texture_rect(opening_background_texture, Rect2(Vector2.ZERO, size), false, Color(0.82, 0.88, 0.84, 0.92))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#0a1111"), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.05, 0.05, 0.42), true)

func _draw_opening_shelf() -> void:
	opening_cards.clear()
	opening_enter_rect = Rect2()
	var font := get_theme_default_font()
	_draw_opening_backdrop()
	var shelf_rect := Rect2(Vector2(42, 32), size - Vector2(84, 94))
	draw_rect(shelf_rect, Color(0.025, 0.055, 0.055, 0.84), true)
	draw_rect(shelf_rect, Color(0.72, 0.82, 0.76, 0.38), false, 1.0)
	draw_string(font, shelf_rect.position + Vector2(28, 42), "LIVING WATERS", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("#f1eadf"))
	draw_string(font, shelf_rect.position + Vector2(30, 68), "Your aquariums, kept alive. Choose a tank to continue.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#b8cbc2"))
	var active_label := "No aquarium selected"
	for item in aquarium_index.get("aquariums", []):
		if str(item.get("id", "")) == _active_aquarium_id():
			active_label = "Active now · %s" % str(item.get("name", "Aquarium"))
			break
	draw_string(font, shelf_rect.position + Vector2(shelf_rect.size.x - 270, 42), active_label, HORIZONTAL_ALIGNMENT_RIGHT, 242, 12, Color("#d6be70"))
	var rack := Rect2(shelf_rect.position + Vector2(28, 94), Vector2(shelf_rect.size.x - 56, shelf_rect.size.y - 156))
	var items: Array = aquarium_index.get("aquariums", [])
	var cols := 2 if size.x < 1050.0 else 3
	var rows := maxi(2, ceili(float(maxi(items.size(), 1)) / float(cols)))
	var gap := 20.0
	var card_w := (rack.size.x - gap * float(cols - 1)) / float(cols)
	var card_h := (rack.size.y - gap * float(rows - 1)) / float(rows)
	for index in range(cols * rows):
		var col := index % cols
		var row := index / cols
		var rect := Rect2(rack.position + Vector2(col * (card_w + gap), row * (card_h + gap)), Vector2(card_w, card_h))
		var item := {}
		if index < items.size() and typeof(items[index]) == TYPE_DICTIONARY:
			item = items[index]
		_draw_opening_tank_card(rect, item, index)
	opening_enter_rect = Rect2(Vector2(size.x - 250, size.y - 70), Vector2(204, 38))
	_draw_opening_button(opening_enter_rect, "Enter active aquarium", true)
	draw_string(font, Vector2(42, size.y - 46), "Click any tank card to enter it. Empty cards are ready for a new setup in Tank.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.82, 0.88, 0.84, 0.78))
	draw_string(font, Vector2(42, size.y - 20), "The aquarium keeps running in the background while you are away.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.64, 0.73, 0.69, 0.75))

func _draw_opening_button(rect: Rect2, label: String, primary: bool) -> void:
	var fill := Color("#d6be70") if primary else Color(0.08, 0.14, 0.14, 0.92)
	var border := Color("#f3df9b") if primary else Color(0.55, 0.65, 0.60, 0.55)
	var ink := Color("#101514") if primary else Color("#e1e3d8")
	draw_rect(rect, fill, true)
	draw_rect(rect, border, false, 1.2)
	draw_string(get_theme_default_font(), rect.position + Vector2(18, rect.size.y * 0.65), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)

func _draw_opening_room_details(rack: Rect2) -> void:
	draw_rect(Rect2(0, rack.end.y + 64, size.x, size.y - rack.end.y), Color("#0b0c0c"), true)
	draw_rect(Rect2(rack.position.x - 118, rack.position.y + 96, 58, 118), Color("#1d2221"), true)
	draw_rect(Rect2(rack.position.x - 106, rack.position.y + 80, 34, 28), Color("#2f4b3c"), true)
	for i in range(10):
		var base := Vector2(rack.position.x - 89 + sin(i) * 8.0, rack.position.y + 84 + i * 5.0)
		draw_line(base, base + Vector2(-24 + i * 5, -42 - i * 4), Color("#64885e"), 2.0, true)
	draw_rect(Rect2(rack.end.x + 46, rack.position.y + 205, 46, 108), Color("#1e2425"), true)
	draw_circle(Vector2(rack.end.x + 69, rack.position.y + 192), 30, Color("#334d41"))
	for i in range(10):
		var root := Vector2(rack.end.x + 68, rack.position.y + 192)
		draw_line(root, root + Vector2(cos(i * 0.62) * 42, -22 - i * 5), Color("#72996b"), 2.0, true)
	draw_rect(Rect2(rack.position.x + 64, rack.end.y + 44, 94, 16), Color("#1d2324"), true)
	draw_rect(Rect2(rack.position.x + 178, rack.end.y + 34, 42, 56), Color("#24444a"), true)
	draw_circle(Vector2(rack.position.x + 245, rack.end.y + 58), 13, Color("#82725d"))
	draw_rect(Rect2(rack.position.x + 268, rack.end.y + 55, 118, 8), Color("#475459"), true)

func _draw_opening_tank_card(rect: Rect2, item: Dictionary, index: int) -> void:
	var font := get_theme_default_font()
	var occupied := not item.is_empty()
	var system := str(item.get("system", "freshwater"))
	var name := str(item.get("name", "Clear starter tank"))
	var litres := float(item.get("gross_litres", 0.0))
	var animals := int(item.get("animals", 0))
	var active := str(item.get("id", "")) == _active_aquarium_id() and occupied
	var glass := Rect2(rect.position + Vector2(10, 12), rect.size - Vector2(20, 46))
	var water_top := Color("#276c77") if system == "freshwater" else Color("#225f84")
	var water_bottom := Color("#123134") if system == "freshwater" else Color("#102b43")
	draw_rect(Rect2(rect.position + Vector2(0, 8), Vector2(rect.size.x, rect.size.y - 8)), Color("#101617"), true)
	draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 17), Vector2(rect.size.x, 17)), Color("#2a241f"), true)
	draw_rect(Rect2(rect.position + Vector2(8, 0), Vector2(rect.size.x - 16, 9)), Color(0.82, 0.94, 0.96, 0.36), true)
	for i in range(8):
		var ratio := float(i) / 7.0
		draw_rect(Rect2(glass.position.x, glass.position.y + glass.size.y * ratio, glass.size.x, glass.size.y / 7.0 + 1.0), water_top.lerp(water_bottom, ratio), true)
	if not occupied:
		draw_rect(glass, Color(0.66, 0.87, 0.92, 0.08), true)
		draw_rect(Rect2(glass.position.x, glass.end.y - 18, glass.size.x, 18), Color("#d8c7a2"), true)
		draw_string(font, glass.position + Vector2(18, glass.size.y * 0.52), "empty glass", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.95, 0.92, 0.52))
	else:
		_draw_opening_substrate(glass, system, index)
		_draw_opening_scape(glass, system, index, animals)
		_draw_opening_filter(glass, index)
	draw_rect(glass, Color(0.76, 0.94, 0.98, 0.34 if active else 0.22), false, 2.0)
	if active:
		draw_rect(rect.grow(4.0), Color("#d6be70"), false, 2.0)
	draw_line(glass.position + Vector2(10, 10), glass.position + Vector2(glass.size.x * 0.44, 10), Color(1, 1, 1, 0.36), 2.0, true)
	var label_rect := Rect2(rect.position + Vector2(16, rect.size.y - 34), Vector2(rect.size.x - 32, 24))
	draw_rect(label_rect, Color("#e4d1b2"), true)
	draw_rect(label_rect, Color("#8c7661"), false, 1.0)
	var title := name
	if title.length() > 23:
		title = title.substr(0, 21) + ".."
	draw_string(font, label_rect.position + Vector2(8, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#1e2422"))
	if occupied:
		draw_string(font, glass.position + Vector2(10, 18), "%.0fL %s  %d animals" % [litres, system, animals], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.88, 0.97, 0.98, 0.70))
		opening_cards.append({"rect": rect, "id": str(item.get("id", ""))})

func _draw_opening_substrate(glass: Rect2, system: String, index: int) -> void:
	var base := Color("#d9c898") if system == "freshwater" else Color("#eee2c8")
	draw_rect(Rect2(glass.position.x, glass.end.y - 28, glass.size.x, 28), base.darkened(0.08), true)
	for i in range(34):
		var x := glass.position.x + fposmod(i * 31.0 + index * 17.0, glass.size.x)
		var y := glass.end.y - 25.0 + fposmod(i * 13.0, 22.0)
		draw_circle(Vector2(x, y), 1.5 + float(i % 3) * 0.7, base.darkened(float(i % 4) * 0.04))

func _draw_opening_scape(glass: Rect2, system: String, index: int, animals: int) -> void:
	var plant_color := Color("#6cbf70") if system == "freshwater" else Color("#87b66e")
	for i in range(8 + index % 4):
		var x := glass.position.x + 26.0 + fposmod(i * 47.0 + index * 19.0, glass.size.x - 52.0)
		var height := 30.0 + float((i * 17 + index) % 48)
		draw_line(Vector2(x, glass.end.y - 28), Vector2(x + sin(i) * 8.0, glass.end.y - 28 - height), plant_color.darkened(float(i % 3) * 0.08), 2.0, true)
		draw_circle(Vector2(x + sin(i) * 8.0, glass.end.y - 28 - height), 5.0, plant_color.lightened(0.08))
	for r in range(3):
		var center := Vector2(glass.position.x + glass.size.x * (0.25 + r * 0.22), glass.end.y - 32.0 - r * 4.0)
		draw_circle(center, 12.0 + r * 3.0, Color("#5f6257"))
	if system == "saltwater":
		for c in range(5):
			var pos := Vector2(glass.position.x + 36 + c * 31, glass.end.y - 44 - float(c % 2) * 10)
			draw_circle(pos, 7.0, Color("#b77991"))
			draw_line(pos, pos + Vector2(0, -18), Color("#d7a27f"), 2.0, true)
	for fish in range(min(animals, 7)):
		var pos := Vector2(glass.position.x + 38 + fposmod(fish * 41 + index * 11, glass.size.x - 76), glass.position.y + 44 + fposmod(fish * 23, glass.size.y - 86))
		var color := Color("#df7d55") if system == "saltwater" else Color("#63c3d9")
		_draw_ellipse(pos, 8.0, 3.0, color)
		draw_polygon(PackedVector2Array([pos + Vector2(-8, 0), pos + Vector2(-15, -5), pos + Vector2(-15, 5)]), [color.darkened(0.15), color.darkened(0.15), color.darkened(0.15)])

func _draw_opening_filter(glass: Rect2, index: int) -> void:
	var x := glass.end.x - 26.0
	draw_rect(Rect2(x, glass.position.y + 24.0, 12.0, 62.0), Color(0.06, 0.08, 0.09, 0.78), true)
	for i in range(4):
		draw_circle(Vector2(x - 7.0 + sin(Time.get_ticks_msec() / 700.0 + i + index) * 2.0, glass.position.y + 76.0 - i * 13.0), 2.0, Color(0.84, 0.96, 1.0, 0.22))

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
	var behavior_payload = _load_json(path.get_base_dir().path_join("behavior_profiles_v1.json"))
	var profiles: Dictionary = behavior_payload.get("profiles", {}) if typeof(behavior_payload) == TYPE_DICTIONARY else {}
	if typeof(payload) == TYPE_DICTIONARY:
		for item in payload.get("species", []):
			var enriched: Dictionary = item.duplicate(true)
			var species_id := str(enriched.get("id", ""))
			if profiles.has(species_id):
				enriched["behavior_profile"] = profiles[species_id]
			result[species_id] = enriched
	return result

func _load_sprite_assets() -> void:
	opening_background_texture = _load_png_texture("res://assets/opening_room.png")
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
		var journal_texture := _load_png_texture("res://assets/journal_sketches/fish_%s.png" % id)
		if journal_texture:
			journal_sketch_textures["fish_" + str(id)] = journal_texture
	for id in [
		"cycle", "water_change", "temperature", "hardscape", "plants", "algae", "coral", "feeding", "equipment",
		"system_notes", "survival_time", "maintenance_chemistry", "stability_memory", "substrate", "plant_memory",
		"coral_memory", "fish_routines", "cleanup_crews", "redox_organics", "disease_stress", "tank_maturity",
		"maintenance_actions", "care_residue", "observations", "sources", "agenda", "compatibility"
	]:
		var chapter_texture := _load_png_texture("res://assets/journal_sketches/%s.png" % id)
		if chapter_texture:
			journal_sketch_textures[id] = chapter_texture
	for id in [
		"river_stone", "moss_stone", "dragon_stone", "branch_driftwood", "root_driftwood",
		"slate_stack", "lava_rock", "manzanita_branch",
		"dwarf_hairgrass", "java_fern", "anubias", "vallisneria", "red_root_floaters",
		"amazon_sword", "cryptocoryne_wendtii", "java_moss", "hornwort",
		"live_rock", "reef_arch", "halimeda_macroalgae", "turtle_grass",
		"zoanthids", "mushroom_coral", "green_star_polyps", "torch_coral", "pulsing_xenia", "kenya_tree_coral"
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
	_load_aquarium_index()
	var payload = _load_json(state_path)
	if typeof(payload) != TYPE_DICTIONARY:
		status_label.text = "Starting ecosystem"
		summary_label.text = "Waiting for the background caretaker to publish the first aquarium state."
		return
	state = payload
	if state.has("aquarium_tabs") and typeof(state["aquarium_tabs"]) == TYPE_DICTIONARY:
		aquarium_index = state["aquarium_tabs"]
	_sync_animals()
	_refresh_ui()
	_refresh_species_options()

func _load_aquarium_index() -> void:
	var payload = _load_json(index_path)
	if typeof(payload) == TYPE_DICTIONARY:
		aquarium_index = payload

func _panel_style(bg: Color, border: Color, radius: int = 14, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func _style_button(button: Button, variant: String = "secondary") -> void:
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	var pressed := StyleBoxFlat.new()
	var disabled := StyleBoxFlat.new()
	var bg := Color("#1d292b")
	var fg := Color("#dde8e5")
	var border := Color("#38575a")
	if variant == "primary":
		bg = Color("#d8c06a")
		fg = Color("#101514")
		border = Color("#f1df9a")
	elif variant == "danger":
		bg = Color("#4a2725")
		fg = Color("#f3c5bd")
		border = Color("#94675e")
	elif variant == "ghost":
		bg = Color(0.10, 0.14, 0.15, 0.46)
		border = Color(0.35, 0.50, 0.50, 0.38)
	normal.bg_color = bg
	normal.border_color = border
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(10)
	hover = normal.duplicate()
	hover.bg_color = bg.lightened(0.08)
	pressed = normal.duplicate()
	pressed.bg_color = bg.darkened(0.08)
	disabled = normal.duplicate()
	disabled.bg_color = Color("#1a2021")
	disabled.border_color = Color("#30393b")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_font_size_override("font_size", 13)

func _style_panel_container(container: PanelContainer, bg: Color = Color(0.07, 0.10, 0.105, 0.86), border: Color = Color("#294248")) -> void:
	container.add_theme_stylebox_override("panel", _panel_style(bg, border))

func _style_field(control: Control, min_size: Vector2 = Vector2(150, 32)) -> void:
	control.custom_minimum_size = min_size
	if control is LineEdit:
		var field := control as LineEdit
		field.add_theme_color_override("font_color", Color("#eef4ee"))
		field.add_theme_color_override("font_placeholder_color", Color(0.72, 0.80, 0.78, 0.62))

func _make_label(text: String, size_px: int = 13, color: Color = Color("#b8cbc7"), wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _make_section(parent: Container, title: String, note: String = "") -> VBoxContainer:
	var card := PanelContainer.new()
	_style_panel_container(card)
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.offset_left = 12
	box.offset_top = 10
	box.offset_right = -12
	box.offset_bottom = -10
	card.add_child(box)
	box.add_child(_make_label(title, 15, Color("#f1ebe0")))
	if note != "":
		box.add_child(_make_label(note, 12, Color("#9fb5b1"), true))
	return box

func _add_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	scroll.clip_contents = true
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(box)
	return box

func _build_ui() -> void:
	title_label = Label.new()
	title_label.text = "Living Waters"
	title_label.position = Vector2(EDGE + 56, 20)
	title_label.add_theme_font_size_override("font_size", 27)
	title_label.add_theme_color_override("font_color", Color("#f2ece0"))
	add_child(title_label)

	status_label = Label.new()
	status_label.text = "Waiting for ecosystem"
	status_label.position = Vector2(EDGE + 58, 52)
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color("#9fbbb7"))
	add_child(status_label)

	side_panel = PanelContainer.new()
	side_panel.name = "SidePanel"
	side_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.070, 0.073, 0.94), Color("#2f4a4f"), 18))
	add_child(side_panel)

	var scroll := ScrollContainer.new()
	scroll.name = "SideScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.clip_contents = true
	side_panel.add_child(scroll)

	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 12)
	panel.offset_left = 16
	panel.offset_top = 14
	panel.offset_right = -16
	panel.offset_bottom = -14
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(panel)

	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	panel.add_child(header)
	header.add_child(_make_label("Keeper tray", 18, Color("#f1ebe0")))
	summary_label = _make_label("The aquarium keeps living in the background.", 12, Color("#a9beb9"), true)
	header.add_child(summary_label)
	aquarium_shelf_button = Button.new()
	aquarium_shelf_button.text = "Aquarium shelf"
	aquarium_shelf_button.custom_minimum_size = Vector2(322, 34)
	_style_button(aquarium_shelf_button, "primary")
	aquarium_shelf_button.pressed.connect(func(): _set_opening_mode(true))
	header.add_child(aquarium_shelf_button)

	var tabs := TabContainer.new()
	keeper_tabs = tabs
	tabs.custom_minimum_size = Vector2(356, 0)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	panel.add_child(tabs)

	var tank_tab := _add_tab(tabs, "Tank")
	var create_box := _make_section(tank_tab, "Start clear", "A new tank begins empty, uncycled, and unfinished on purpose.")
	tank_name_edit = LineEdit.new()
	tank_name_edit.placeholder_text = "Tank name"
	tank_name_edit.text = "Clear 60L"
	_style_field(tank_name_edit, Vector2(322, 32))
	create_box.add_child(tank_name_edit)
	var tank_form := GridContainer.new()
	tank_form.columns = 2
	tank_form.add_theme_constant_override("h_separation", 8)
	tank_form.add_theme_constant_override("v_separation", 8)
	create_box.add_child(tank_form)
	tank_litres_spin = SpinBox.new()
	tank_litres_spin.min_value = 12
	tank_litres_spin.max_value = 900
	tank_litres_spin.step = 1
	tank_litres_spin.value = 60
	tank_litres_spin.suffix = " L"
	_style_field(tank_litres_spin, Vector2(154, 32))
	tank_form.add_child(tank_litres_spin)
	tank_system_select = OptionButton.new()
	_style_field(tank_system_select, Vector2(154, 32))
	tank_system_select.add_item("Freshwater")
	tank_system_select.set_item_metadata(0, "freshwater")
	tank_system_select.add_item("Saltwater")
	tank_system_select.set_item_metadata(1, "saltwater")
	tank_form.add_child(tank_system_select)
	var create_tank := Button.new()
	create_tank.text = "Create empty tank"
	create_tank.custom_minimum_size = Vector2(322, 36)
	_style_button(create_tank, "primary")
	create_tank.pressed.connect(func(): _create_clear_aquarium())
	create_box.add_child(create_tank)

	var system_box := _make_section(tank_tab, "Water type", "Changing systems clears incompatible life. It belongs here, away from daily buttons.")
	var system_row := HBoxContainer.new()
	system_row.add_theme_constant_override("separation", 8)
	system_box.add_child(system_row)
	var fresh := Button.new()
	fresh.text = "Freshwater"
	fresh.custom_minimum_size = Vector2(154, 34)
	_style_button(fresh)
	fresh.pressed.connect(func(): _write_command({"action": "switch_system", "system": "freshwater"}))
	system_row.add_child(fresh)
	var reef := Button.new()
	reef.text = "Saltwater"
	reef.custom_minimum_size = Vector2(154, 34)
	_style_button(reef)
	reef.pressed.connect(func(): _write_command({"action": "switch_system", "system": "saltwater"}))
	system_row.add_child(reef)

	var substrate_box := _make_section(tank_tab, "Substrate", "Depth changes habitat, rooting, trapped mulm, and cleaning behavior.")
	var substrate_row := GridContainer.new()
	substrate_row.columns = 2
	substrate_row.add_theme_constant_override("h_separation", 8)
	substrate_row.add_theme_constant_override("v_separation", 8)
	substrate_box.add_child(substrate_row)
	substrate_select = OptionButton.new()
	_style_field(substrate_select, Vector2(154, 32))
	_add_substrate_choice("Fine sand", "fine_sand")
	_add_substrate_choice("Rounded gravel", "rounded_gravel")
	_add_substrate_choice("Planted soil", "planted_soil")
	_add_substrate_choice("Reef sand", "reef_sand")
	_add_substrate_choice("Bare bottom", "bare_bottom")
	substrate_row.add_child(substrate_select)
	substrate_depth_spin = SpinBox.new()
	substrate_depth_spin.min_value = 0
	substrate_depth_spin.max_value = 9
	substrate_depth_spin.step = 0.5
	substrate_depth_spin.value = 5
	substrate_depth_spin.suffix = " cm"
	_style_field(substrate_depth_spin, Vector2(154, 32))
	substrate_row.add_child(substrate_depth_spin)
	var apply_substrate := Button.new()
	apply_substrate.text = "Apply substrate"
	apply_substrate.custom_minimum_size = Vector2(322, 34)
	_style_button(apply_substrate)
	apply_substrate.pressed.connect(func(): _apply_substrate())
	substrate_box.add_child(apply_substrate)

	var care_tab := _add_tab(tabs, "Care")
	var quick_box := _make_section(care_tab, "Today", "Small actions first. Water changes expose the replacement-water details before you press the button.")
	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 8)
	quick_box.add_child(quick_row)
	var feed := Button.new()
	feed.text = "Feed"
	feed.custom_minimum_size = Vector2(101, 38)
	_style_button(feed, "primary")
	feed.pressed.connect(func(): _write_command(_feed_command()))
	quick_row.add_child(feed)
	var test_button := Button.new()
	test_button.text = "Test"
	test_button.custom_minimum_size = Vector2(101, 38)
	_style_button(test_button)
	test_button.pressed.connect(func(): _write_command(COMMAND_TEST_WATER.duplicate()))
	quick_row.add_child(test_button)
	var maintenance_button := Button.new()
	maintenance_button.text = "Weekly"
	maintenance_button.custom_minimum_size = Vector2(101, 38)
	_style_button(maintenance_button)
	maintenance_button.pressed.connect(func(): _write_command(COMMAND_WEEKLY_MAINTENANCE.duplicate()))
	quick_row.add_child(maintenance_button)
	food_select = OptionButton.new()
	food_select.fit_to_longest_item = false
	food_select.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_style_field(food_select, Vector2(322, 32))
	for option in FOOD_OPTIONS:
		food_select.add_item("%s - %s" % [str(option["label"]), str(option["hint"])])
		food_select.set_item_metadata(food_select.item_count - 1, str(option["id"]))
	quick_box.add_child(food_select)
	var small_care_row := HBoxContainer.new()
	small_care_row.add_theme_constant_override("separation", 8)
	quick_box.add_child(small_care_row)
	var remove_food := Button.new()
	remove_food.text = "Leftovers"
	remove_food.custom_minimum_size = Vector2(101, 34)
	_style_button(remove_food)
	remove_food.pressed.connect(func(): _write_command(COMMAND_REMOVE_FOOD.duplicate()))
	small_care_row.add_child(remove_food)
	var scrape_algae := Button.new()
	scrape_algae.text = "Scrape"
	scrape_algae.custom_minimum_size = Vector2(101, 34)
	_style_button(scrape_algae)
	scrape_algae.pressed.connect(func(): _write_command(COMMAND_SCRAPE_ALGAE.duplicate()))
	small_care_row.add_child(scrape_algae)
	var trim_plants := Button.new()
	trim_plants.text = "Trim"
	trim_plants.custom_minimum_size = Vector2(101, 34)
	_style_button(trim_plants)
	trim_plants.pressed.connect(func(): _write_command(COMMAND_TRIM_PLANTS.duplicate()))
	small_care_row.add_child(trim_plants)
	var reef_care_row := HBoxContainer.new()
	reef_care_row.add_theme_constant_override("separation", 8)
	quick_box.add_child(reef_care_row)
	var top_off := Button.new()
	top_off.text = "Top off"
	top_off.custom_minimum_size = Vector2(154, 34)
	_style_button(top_off)
	top_off.pressed.connect(func(): _write_command(COMMAND_TOP_OFF.duplicate()))
	reef_care_row.add_child(top_off)
	var empty_skimmer := Button.new()
	empty_skimmer.text = "Empty skimmer"
	empty_skimmer.custom_minimum_size = Vector2(154, 34)
	_style_button(empty_skimmer)
	empty_skimmer.pressed.connect(func(): _write_command(COMMAND_EMPTY_SKIMMER.duplicate()))
	reef_care_row.add_child(empty_skimmer)
	var minerals := Button.new()
	minerals.text = "Dose minerals"
	minerals.custom_minimum_size = Vector2(322, 34)
	_style_button(minerals, "ghost")
	minerals.pressed.connect(func(): _write_command(COMMAND_DOSE_MINERALS.duplicate()))
	quick_box.add_child(minerals)

	var water_box := _make_section(care_tab, "Water change", "Match temperature, pH, and hardness. Disturbing substrate can release old waste.")
	var water_change_grid := GridContainer.new()
	water_change_grid.columns = 2
	water_change_grid.add_theme_constant_override("h_separation", 8)
	water_change_grid.add_theme_constant_override("v_separation", 8)
	water_box.add_child(water_change_grid)
	replacement_temp_spin = SpinBox.new()
	replacement_temp_spin.min_value = 8
	replacement_temp_spin.max_value = 34
	replacement_temp_spin.step = 0.5
	replacement_temp_spin.value = 23
	replacement_temp_spin.suffix = " C"
	_style_field(replacement_temp_spin, Vector2(154, 32))
	water_change_grid.add_child(replacement_temp_spin)
	replacement_ph_spin = SpinBox.new()
	replacement_ph_spin.min_value = 4.5
	replacement_ph_spin.max_value = 9.2
	replacement_ph_spin.step = 0.1
	replacement_ph_spin.value = 7.0
	replacement_ph_spin.suffix = " pH"
	_style_field(replacement_ph_spin, Vector2(154, 32))
	water_change_grid.add_child(replacement_ph_spin)
	replacement_gh_spin = SpinBox.new()
	replacement_gh_spin.min_value = 0
	replacement_gh_spin.max_value = 30
	replacement_gh_spin.step = 1
	replacement_gh_spin.value = 7
	replacement_gh_spin.suffix = " dGH"
	_style_field(replacement_gh_spin, Vector2(154, 32))
	water_change_grid.add_child(replacement_gh_spin)
	disturb_substrate_check = CheckBox.new()
	disturb_substrate_check.text = "Disturb bed"
	disturb_substrate_check.custom_minimum_size = Vector2(154, 32)
	water_change_grid.add_child(disturb_substrate_check)
	var change := Button.new()
	change.text = "Change 25%"
	change.custom_minimum_size = Vector2(322, 38)
	_style_button(change, "primary")
	change.pressed.connect(func(): _write_command(_water_change_command()))
	water_box.add_child(change)

	var equipment_tab := _add_tab(tabs, "Equipment")
	var equipment_box := _make_section(equipment_tab, "Equipment bench", "Tune the visible devices inside the tank, then refresh carbon and phosphate media when it clogs.")
	var equipment_grid := GridContainer.new()
	equipment_grid.columns = 2
	equipment_grid.add_theme_constant_override("h_separation", 8)
	equipment_grid.add_theme_constant_override("v_separation", 8)
	equipment_box.add_child(equipment_grid)
	filter_flow_spin = SpinBox.new()
	filter_flow_spin.min_value = 8
	filter_flow_spin.max_value = 100
	filter_flow_spin.step = 2
	filter_flow_spin.value = 78
	filter_flow_spin.suffix = "% flow"
	_style_field(filter_flow_spin, Vector2(154, 32))
	equipment_grid.add_child(filter_flow_spin)
	heater_target_spin = SpinBox.new()
	heater_target_spin.min_value = 16
	heater_target_spin.max_value = 31
	heater_target_spin.step = 0.5
	heater_target_spin.value = 24
	heater_target_spin.suffix = " C"
	_style_field(heater_target_spin, Vector2(154, 32))
	equipment_grid.add_child(heater_target_spin)
	light_hours_spin = SpinBox.new()
	light_hours_spin.min_value = 0
	light_hours_spin.max_value = 14
	light_hours_spin.step = 0.5
	light_hours_spin.value = 8
	light_hours_spin.suffix = " h light"
	_style_field(light_hours_spin, Vector2(154, 32))
	equipment_grid.add_child(light_hours_spin)
	air_output_spin = SpinBox.new()
	air_output_spin.min_value = 0
	air_output_spin.max_value = 100
	air_output_spin.step = 5
	air_output_spin.value = 50
	air_output_spin.suffix = "% air"
	_style_field(air_output_spin, Vector2(154, 32))
	equipment_grid.add_child(air_output_spin)
	var equipment_actions := HBoxContainer.new()
	equipment_actions.add_theme_constant_override("separation", 8)
	equipment_box.add_child(equipment_actions)
	var apply_equipment := Button.new()
	apply_equipment.text = "Apply"
	apply_equipment.custom_minimum_size = Vector2(154, 34)
	_style_button(apply_equipment)
	apply_equipment.pressed.connect(func(): _apply_equipment())
	equipment_actions.add_child(apply_equipment)
	var service_filter := Button.new()
	service_filter.text = "Refresh media"
	service_filter.custom_minimum_size = Vector2(154, 34)
	_style_button(service_filter)
	service_filter.pressed.connect(func(): _write_command(COMMAND_SERVICE_FILTER.duplicate()))
	equipment_actions.add_child(service_filter)
	var dose_ammonia := Button.new()
	dose_ammonia.text = "Dose fishless cycle"
	dose_ammonia.custom_minimum_size = Vector2(322, 32)
	_style_button(dose_ammonia, "ghost")
	dose_ammonia.pressed.connect(func(): _write_command(COMMAND_DOSE_AMMONIA.duplicate()))
	equipment_box.add_child(dose_ammonia)
	var safeguards := Button.new()
	safeguards.text = "Fit safety & outage kit"
	safeguards.custom_minimum_size = Vector2(322, 34)
	_style_button(safeguards, "ghost")
	safeguards.pressed.connect(func(): _write_command({"action": "install_safeguards"}))
	equipment_box.add_child(safeguards)

	var life_tab := _add_tab(tabs, "Life")
	var species_box := _make_section(life_tab, "Livestock bench", "Choose an animal here, then use the full keeper journal for research before acclimation.")
	species_select = OptionButton.new()
	_style_field(species_select, Vector2(322, 32))
	species_select.item_selected.connect(func(_index): notebook_page_index = 0; _refresh_research_card())
	species_box.add_child(species_select)
	notebook_button = Button.new()
	notebook_button.text = "Open keeper journal"
	notebook_button.custom_minimum_size = Vector2(322, 34)
	_style_button(notebook_button)
	notebook_button.pressed.connect(func(): _toggle_notebook())
	species_box.add_child(notebook_button)
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	species_box.add_child(add_row)
	var add_good := Button.new()
	add_good.text = "Acclimate net"
	add_good.custom_minimum_size = Vector2(154, 34)
	_style_button(add_good, "primary")
	add_good.pressed.connect(func(): _add_selected_animal(true))
	add_row.add_child(add_good)
	var add_bad := Button.new()
	add_bad.text = "Skip acclimation"
	add_bad.custom_minimum_size = Vector2(154, 34)
	_style_button(add_bad, "danger")
	add_bad.pressed.connect(func(): _add_selected_animal(false))
	add_row.add_child(add_bad)
	var animal_box := _make_section(life_tab, "Residents", "Select a resident to remove it. The aquarium drawing remains the main place to observe behavior.")
	animal_list = ItemList.new()
	animal_list.custom_minimum_size = Vector2(322, 178)
	animal_list.item_selected.connect(func(index): _select_animal(index))
	animal_box.add_child(animal_list)
	var remove_animal := Button.new()
	remove_animal.text = "Remove selected animal"
	remove_animal.custom_minimum_size = Vector2(322, 34)
	_style_button(remove_animal, "danger")
	remove_animal.pressed.connect(func(): _remove_selected_animal())
	animal_box.add_child(remove_animal)
	var health_row := HBoxContainer.new()
	health_row.add_theme_constant_override("separation", 8)
	animal_box.add_child(health_row)
	var quarantine := Button.new()
	quarantine.text = "Quarantine"
	quarantine.custom_minimum_size = Vector2(154, 34)
	_style_button(quarantine)
	quarantine.pressed.connect(func(): _quarantine_selected_animal())
	health_row.add_child(quarantine)
	var treat := Button.new()
	treat.text = "Treat outbreak"
	treat.custom_minimum_size = Vector2(154, 34)
	_style_button(treat, "ghost")
	treat.pressed.connect(func(): _write_command(COMMAND_TREAT_OUTBREAK.duplicate()))
	health_row.add_child(treat)

	var scape_tab := _add_tab(tabs, "Scape")
	var scape_box := _make_section(scape_tab, "Scape studio", "Compose the aquarium piece by piece. Rooted plants need substrate, floaters need surface, and every placed piece stays editable.")
	scape_label = _make_label("", 12, Color("#9fb5b1"), true)
	scape_box.add_child(scape_label)
	tool_label = _make_label("Choose a piece, set its shape, then place it on the canvas.", 12, Color("#e1cd87"), true)
	scape_box.add_child(tool_label)

	var transform_box := _make_section(scape_tab, "Object editor", "Use these settings for a new piece or select an existing piece in the aquarium to transform it.")
	scape_selection_label = _make_label("No piece selected. Placement settings are ready.", 12, Color("#d8eee9"), true)
	transform_box.add_child(scape_selection_label)
	var transform_grid := GridContainer.new()
	transform_grid.columns = 2
	transform_grid.add_theme_constant_override("h_separation", 8)
	transform_grid.add_theme_constant_override("v_separation", 8)
	transform_box.add_child(transform_grid)
	scape_scale_spin = SpinBox.new()
	scape_scale_spin.min_value = 0.35
	scape_scale_spin.max_value = 2.4
	scape_scale_spin.step = 0.05
	scape_scale_spin.value = 1.0
	scape_scale_spin.suffix = "x scale"
	_style_field(scape_scale_spin, Vector2(154, 32))
	transform_grid.add_child(scape_scale_spin)
	scape_rotation_spin = SpinBox.new()
	scape_rotation_spin.min_value = -180
	scape_rotation_spin.max_value = 180
	scape_rotation_spin.step = 5
	scape_rotation_spin.value = 0
	scape_rotation_spin.suffix = " deg"
	_style_field(scape_rotation_spin, Vector2(154, 32))
	transform_grid.add_child(scape_rotation_spin)
	scape_layer_select = OptionButton.new()
	_style_field(scape_layer_select, Vector2(154, 32))
	scape_layer_select.add_item("Back layer")
	scape_layer_select.set_item_metadata(0, 0)
	scape_layer_select.add_item("Mid layer")
	scape_layer_select.set_item_metadata(1, 1)
	scape_layer_select.add_item("Front layer")
	scape_layer_select.set_item_metadata(2, 2)
	scape_layer_select.select(1)
	transform_grid.add_child(scape_layer_select)
	scape_flip_check = CheckBox.new()
	scape_flip_check.text = "Mirror piece"
	scape_flip_check.custom_minimum_size = Vector2(154, 32)
	transform_grid.add_child(scape_flip_check)
	var transform_actions := HBoxContainer.new()
	transform_actions.add_theme_constant_override("separation", 8)
	transform_box.add_child(transform_actions)
	var apply_transform := Button.new()
	apply_transform.text = "Apply"
	apply_transform.custom_minimum_size = Vector2(101, 34)
	_style_button(apply_transform, "primary")
	apply_transform.pressed.connect(func(): _apply_selected_scape_transform())
	transform_actions.add_child(apply_transform)
	var duplicate_scape := Button.new()
	duplicate_scape.text = "Duplicate"
	duplicate_scape.custom_minimum_size = Vector2(101, 34)
	_style_button(duplicate_scape)
	duplicate_scape.pressed.connect(func(): _duplicate_selected_scape())
	transform_actions.add_child(duplicate_scape)
	var remove_scape := Button.new()
	remove_scape.text = "Remove"
	remove_scape.custom_minimum_size = Vector2(101, 34)
	_style_button(remove_scape, "danger")
	remove_scape.pressed.connect(func(): _remove_selected_scape())
	transform_actions.add_child(remove_scape)
	var select_mode := Button.new()
	select_mode.text = "Select / move a piece"
	select_mode.custom_minimum_size = Vector2(322, 34)
	_style_button(select_mode, "ghost")
	select_mode.pressed.connect(func():
		selected_scape_tool = {}
		selected_animal_tool = {}
		if tool_label:
			tool_label.text = "Selection mode active. Click a piece, then click empty water to move it."
	)
	transform_box.add_child(select_mode)
	var nudge_row := HBoxContainer.new()
	nudge_row.add_theme_constant_override("separation", 6)
	transform_box.add_child(nudge_row)
	for item in [["←", Vector2(-0.015, 0.0)], ["→", Vector2(0.015, 0.0)], ["↑", Vector2(0.0, -0.015)], ["↓", Vector2(0.0, 0.015)]]:
		var nudge := Button.new()
		nudge.text = str(item[0])
		nudge.custom_minimum_size = Vector2(75, 32)
		_style_button(nudge)
		var delta: Vector2 = item[1]
		nudge.pressed.connect(func(): _nudge_selected_scape(delta))
		nudge_row.add_child(nudge)
	var rotate_row := HBoxContainer.new()
	rotate_row.add_theme_constant_override("separation", 8)
	transform_box.add_child(rotate_row)
	var rotate_left := Button.new()
	rotate_left.text = "Rotate -15°"
	rotate_left.custom_minimum_size = Vector2(154, 32)
	_style_button(rotate_left)
	rotate_left.pressed.connect(func(): _rotate_selected_scape(-15.0))
	rotate_row.add_child(rotate_left)
	var rotate_right := Button.new()
	rotate_right.text = "Rotate +15°"
	rotate_right.custom_minimum_size = Vector2(154, 32)
	_style_button(rotate_right)
	rotate_right.pressed.connect(func(): _rotate_selected_scape(15.0))
	rotate_row.add_child(rotate_right)

	var hardscape_box := _make_section(scape_tab, "Hardscape library")
	var hardscape_grid := GridContainer.new()
	hardscape_grid.columns = 2
	hardscape_grid.add_theme_constant_override("h_separation", 8)
	hardscape_grid.add_theme_constant_override("v_separation", 8)
	hardscape_box.add_child(hardscape_grid)
	_add_scape_button(hardscape_grid, "River stone", "rocks", "river_stone")
	_add_scape_button(hardscape_grid, "Moss stone", "rocks", "moss_stone")
	_add_scape_button(hardscape_grid, "Slate stack", "rocks", "slate_stack")
	_add_scape_button(hardscape_grid, "Lava rock", "rocks", "lava_rock")
	_add_scape_button(hardscape_grid, "Live rock", "rocks", "live_rock")
	_add_scape_button(hardscape_grid, "Reef arch", "rocks", "reef_arch")
	_add_scape_button(hardscape_grid, "Branch log", "wood", "branch_driftwood")
	_add_scape_button(hardscape_grid, "Root wood", "wood", "root_driftwood")
	_add_scape_button(hardscape_grid, "Manzanita", "wood", "manzanita_branch")

	var plant_box := _make_section(scape_tab, "Plant library")
	var plant_grid := GridContainer.new()
	plant_grid.columns = 2
	plant_grid.add_theme_constant_override("h_separation", 8)
	plant_grid.add_theme_constant_override("v_separation", 8)
	plant_box.add_child(plant_grid)
	_add_scape_button(plant_grid, "Hairgrass", "plants", "dwarf_hairgrass")
	_add_scape_button(plant_grid, "Vallisneria", "plants", "vallisneria")
	_add_scape_button(plant_grid, "Java fern", "plants", "java_fern")
	_add_scape_button(plant_grid, "Amazon sword", "plants", "amazon_sword")
	_add_scape_button(plant_grid, "Crypt", "plants", "cryptocoryne_wendtii")
	_add_scape_button(plant_grid, "Java moss", "plants", "java_moss")
	_add_scape_button(plant_grid, "Hornwort", "plants", "hornwort")
	_add_scape_button(plant_grid, "Floaters", "plants", "red_root_floaters")
	_add_scape_button(plant_grid, "Halimeda", "plants", "halimeda_macroalgae")

	var coral_box := _make_section(scape_tab, "Reef library")
	var coral_grid := GridContainer.new()
	coral_grid.columns = 2
	coral_grid.add_theme_constant_override("h_separation", 8)
	coral_grid.add_theme_constant_override("v_separation", 8)
	coral_box.add_child(coral_grid)
	_add_scape_button(coral_grid, "Zoanthids", "corals", "zoanthids")
	_add_scape_button(coral_grid, "Mushroom coral", "corals", "mushroom_coral")
	_add_scape_button(coral_grid, "Star polyps", "corals", "green_star_polyps")
	_add_scape_button(coral_grid, "Torch coral", "corals", "torch_coral")
	_add_scape_button(coral_grid, "Xenia", "corals", "pulsing_xenia")
	_add_scape_button(coral_grid, "Kenya tree", "corals", "kenya_tree_coral")

	var scape_actions := HBoxContainer.new()
	scape_actions.add_theme_constant_override("separation", 8)
	scape_tab.add_child(scape_actions)
	var reset_scape := Button.new()
	reset_scape.text = "Starter scape"
	reset_scape.custom_minimum_size = Vector2(154, 34)
	_style_button(reset_scape)
	reset_scape.pressed.connect(func(): _clear_scape_editor(); _write_command({"action": "reset_scape"}))
	scape_actions.add_child(reset_scape)
	var clear_scape_button := Button.new()
	clear_scape_button.text = "Clear canvas"
	clear_scape_button.custom_minimum_size = Vector2(154, 34)
	_style_button(clear_scape_button, "danger")
	clear_scape_button.pressed.connect(func(): _clear_scape_editor(); _write_command({"action": "clear_scape"}))
	scape_actions.add_child(clear_scape_button)

	_build_notebook_overlay()
	_refresh_species_options()
	_layout_ui()
	_set_opening_mode(true)
	return

func _add_scape_button(parent: Container, text: String, category: String, item_type: String, quantity: int = 1) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(154, 42)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if scape_textures.has(item_type):
		button.icon = scape_textures[item_type]
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 30)
	_style_button(button, "ghost")
	button.pressed.connect(func(): _choose_scape_tool(category, item_type, text))
	parent.add_child(button)

func _build_notebook_overlay() -> void:
	notebook_panel = PanelContainer.new()
	notebook_panel.name = "KeeperJournal"
	notebook_panel.visible = false
	notebook_panel.modulate.a = 0.0
	notebook_panel.clip_contents = true
	notebook_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.018, 0.015, 0.62), Color(0, 0, 0, 0), 0, 0))
	add_child(notebook_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	outer.offset_left = 26
	outer.offset_top = 20
	outer.offset_right = -26
	outer.offset_bottom = -18
	notebook_panel.add_child(outer)

	var spread := HBoxContainer.new()
	spread.add_theme_constant_override("separation", 0)
	spread.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spread.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(spread)
	var left_page := _notebook_page()
	var right_page := _notebook_page()
	notebook_left_page = left_page
	notebook_right_page = right_page
	spread.add_child(left_page)
	var spine := PanelContainer.new()
	spine.custom_minimum_size = Vector2(24, 0)
	spine.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spine.add_theme_stylebox_override("panel", _panel_style(Color("#7c5f38"), Color("#5b4022"), 0, 0))
	spread.add_child(spine)
	spread.add_child(right_page)
	notebook_left_page_label = left_page.get_node("PageBox/PageNumber") as Label
	notebook_right_page_label = right_page.get_node("PageBox/PageNumber") as Label
	notebook_left_sketch = left_page.get_node("PageBox/PageSketch") as TextureRect
	notebook_right_sketch = right_page.get_node("PageBox/PageSketch") as TextureRect
	research_label = left_page.get_node("PageBox/PageScroll/PageContent/PageText") as Label
	notebook_right_label = right_page.get_node("PageBox/PageScroll/PageContent/PageText") as Label

	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 10)
	outer.add_child(controls)
	notebook_prev_button = Button.new()
	notebook_prev_button.text = "<"
	notebook_prev_button.custom_minimum_size = Vector2(52, 34)
	_style_button(notebook_prev_button)
	notebook_prev_button.pressed.connect(func(): _turn_notebook(-2))
	controls.add_child(notebook_prev_button)
	notebook_index_select = OptionButton.new()
	notebook_index_select.custom_minimum_size = Vector2(260, 34)
	_style_field(notebook_index_select, Vector2(260, 34))
	notebook_index_select.item_selected.connect(func(index): _jump_notebook_to(index))
	controls.add_child(notebook_index_select)
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(176, 36)
	_style_button(done)
	done.pressed.connect(func(): _toggle_notebook(false))
	controls.add_child(done)
	notebook_next_button = Button.new()
	notebook_next_button.text = ">"
	notebook_next_button.custom_minimum_size = Vector2(52, 34)
	_style_button(notebook_next_button)
	notebook_next_button.pressed.connect(func(): _turn_notebook(2))
	controls.add_child(notebook_next_button)
	_set_notebook_entries(["Choose a species to begin the journal.", "The journal will combine species research with your current tank chemistry, scape, equipment, and recent risks."])

func _notebook_page() -> PanelContainer:
	var page := PanelContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_stylebox_override("panel", _panel_style(Color("#e7d7ad"), Color("#8d7046"), 4, 2))
	var page_box := VBoxContainer.new()
	page_box.name = "PageBox"
	page_box.offset_left = 18
	page_box.offset_top = 12
	page_box.offset_right = -18
	page_box.offset_bottom = -14
	page.add_child(page_box)
	var page_number := _make_label("Page", 13, Color("#735d3a"))
	page_number.name = "PageNumber"
	page_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_box.add_child(page_number)
	var scroll := ScrollContainer.new()
	scroll.name = "PageScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_box.add_child(scroll)
	var page_content := VBoxContainer.new()
	page_content.name = "PageContent"
	page_content.add_theme_constant_override("separation", 12)
	page_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(page_content)
	var text := _make_label("", 15, Color("#2d2418"), true)
	text.name = "PageText"
	text.add_theme_constant_override("line_spacing", 4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	page_content.add_child(text)
	var sketch := TextureRect.new()
	sketch.name = "PageSketch"
	sketch.custom_minimum_size = Vector2(0, 112)
	sketch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sketch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sketch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sketch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sketch.modulate = Color(0.25, 0.20, 0.14, 0.90)
	page_content.add_child(sketch)
	return page

func _layout_ui() -> void:
	var side_panel := get_node_or_null("SidePanel") as PanelContainer
	if side_panel:
		side_panel.position = Vector2(size.x - PANEL_WIDTH - EDGE, TOP_BAR)
		side_panel.size = Vector2(PANEL_WIDTH, max(560.0, size.y - TOP_BAR - EDGE))
		var side_scroll := side_panel.get_node_or_null("SideScroll") as ScrollContainer
		if side_scroll:
			side_scroll.size = side_panel.size
		if keeper_tabs:
			keeper_tabs.custom_minimum_size = Vector2(PANEL_WIDTH - 32.0, max(430.0, side_panel.size.y - 126.0))
	if notebook_panel:
		var margin := Vector2(max(38.0, size.x * 0.055), max(34.0, size.y * 0.055))
		notebook_panel.position = margin
		notebook_panel.size = Vector2(max(640.0, size.x - margin.x * 2.0), max(430.0, size.y - margin.y * 2.0))
		notebook_panel.pivot_offset = notebook_panel.size * 0.5

func _add_substrate_choice(label: String, id: String) -> void:
	if not substrate_select:
		return
	substrate_select.add_item(label)
	substrate_select.set_item_metadata(substrate_select.item_count - 1, id)

func _apply_substrate() -> void:
	if not substrate_select or substrate_select.selected < 0:
		return
	var substrate := str(substrate_select.get_item_metadata(substrate_select.selected))
	var depth := 5.0
	if substrate_depth_spin:
		depth = float(substrate_depth_spin.value)
	_write_command({"action": "set_substrate", "substrate": substrate, "depth_cm": depth})

func _water_change_command() -> Dictionary:
	var command := COMMAND_WATER_CHANGE.duplicate()
	if replacement_temp_spin:
		command["replacement_temp_c"] = float(replacement_temp_spin.value)
	if replacement_ph_spin:
		command["replacement_ph"] = float(replacement_ph_spin.value)
	if replacement_gh_spin:
		command["replacement_gh_dgh"] = float(replacement_gh_spin.value)
	if disturb_substrate_check:
		command["disturbed_substrate"] = bool(disturb_substrate_check.button_pressed)
	command["conditioner_dose"] = 1.0
	return command

func _feed_command() -> Dictionary:
	var command := COMMAND_FEED.duplicate()
	var total_bioload := 0.0
	var total_hunger := 0.0
	var living := 0
	for animal in state.get("animals", []):
		if not bool(animal.get("alive", true)):
			continue
		var spec: Dictionary = species.get(str(animal.get("species_id", "")), {})
		total_bioload += float(spec.get("bioload", 0.5))
		total_hunger += float(animal.get("hunger", 0.35))
		living += 1
	var average_hunger: float = total_hunger / max(1.0, float(living))
	command["amount"] = clamp(total_bioload * 0.14 * (0.65 + average_hunger), 0.16, 1.5) if living > 0 else 0.16
	if food_select and food_select.selected >= 0:
		command["food_type"] = str(food_select.get_item_metadata(food_select.selected))
	return command

func _apply_equipment() -> void:
	if filter_flow_spin:
		_write_command({"action": "set_equipment", "equipment": "filter", "enabled": true, "value": float(filter_flow_spin.value) / 100.0})
	if heater_target_spin:
		_write_command({"action": "set_equipment", "equipment": "heater", "enabled": true, "value": float(heater_target_spin.value)})
	if light_hours_spin:
		_write_command({"action": "set_equipment", "equipment": "light", "enabled": float(light_hours_spin.value) > 0.0, "value": float(light_hours_spin.value)})
	if air_output_spin:
		_write_command({"action": "set_equipment", "equipment": "air_pump", "enabled": float(air_output_spin.value) > 0.0, "value": float(air_output_spin.value) / 100.0})
	if tool_label:
		tool_label.text = "Equipment adjustments queued. Watch oxygen, temperature, flow, algae, and plant/coral response."

func _sync_substrate_controls() -> void:
	if not substrate_select:
		return
	var aquarium = state.get("aquarium", {})
	var substrate := str(aquarium.get("substrate", "fine_sand"))
	for i in range(substrate_select.item_count):
		if str(substrate_select.get_item_metadata(i)) == substrate:
			substrate_select.select(i)
			break
	if substrate_depth_spin:
		substrate_depth_spin.value = float(aquarium.get("substrate_depth_cm", 5.0))

func _sync_equipment_controls() -> void:
	var equipment = state.get("equipment", {})
	var filter = equipment.get("filter", {})
	var heater = equipment.get("heater", {})
	var light = equipment.get("light", {})
	var air = equipment.get("air_pump", {})
	if filter_flow_spin:
		filter_flow_spin.value = float(filter.get("flow", 0.78)) * 100.0
	if heater_target_spin:
		heater_target_spin.value = float(heater.get("target_c", state.get("water", {}).get("temperature_c", 24.0)))
	if light_hours_spin:
		light_hours_spin.value = float(light.get("hours_per_day", 8.0)) if bool(light.get("enabled", true)) else 0.0
	if air_output_spin:
		air_output_spin.value = float(air.get("output", 0.5)) * 100.0 if bool(air.get("enabled", true)) else 0.0

func _sync_food_controls() -> void:
	if not food_select:
		return
	var food = state.get("food", {})
	var last_type := str(food.get("last_type", "community_flake"))
	if last_type == synced_food_type:
		return
	for i in range(food_select.item_count):
		if str(food_select.get_item_metadata(i)) == last_type:
			food_select.select(i)
			synced_food_type = last_type
			return

func _toggle_notebook(force_open = null) -> void:
	notebook_open = (not notebook_open) if force_open == null else bool(force_open)
	if notebook_button:
		notebook_button.text = "Close keeper journal" if notebook_open else "Open keeper journal"
	if notebook_open:
		_refresh_research_card()

func _update_notebook_animation(delta: float) -> void:
	if not notebook_panel:
		return
	if opening_screen:
		notebook_panel.visible = false
		return
	var target := 1.0 if notebook_open else 0.0
	notebook_amount = move_toward(notebook_amount, target, delta * 5.5)
	var eased := 1.0 - pow(1.0 - notebook_amount, 3.0)
	notebook_panel.modulate.a = lerp(0.0, 1.0, eased)
	notebook_panel.scale = Vector2(lerp(0.965, 1.0, eased), lerp(0.92, 1.0, eased))
	notebook_panel.visible = notebook_amount > 0.02 or notebook_open
	if notebook_turn_amount > 0.0:
		notebook_turn_amount = move_toward(notebook_turn_amount, 0.0, delta / 0.24)
		var turn_progress := 1.0 - notebook_turn_amount
		var turn_eased := 1.0 - pow(1.0 - turn_progress, 3.0)
		var turning_page := notebook_right_page if notebook_turn_direction > 0 else notebook_left_page
		var resting_page := notebook_left_page if notebook_turn_direction > 0 else notebook_right_page
		if turning_page:
			turning_page.pivot_offset = Vector2(0.0 if notebook_turn_direction > 0 else turning_page.size.x, turning_page.size.y * 0.5)
			turning_page.scale = Vector2(lerp(0.84, 1.0, turn_eased), lerp(0.985, 1.0, turn_eased))
			turning_page.modulate.a = lerp(0.42, 1.0, turn_eased)
		if resting_page:
			resting_page.scale = Vector2(lerp(0.985, 1.0, turn_eased), 1.0)
			resting_page.modulate.a = 1.0
	elif notebook_left_page and notebook_right_page:
		notebook_left_page.scale = Vector2.ONE
		notebook_right_page.scale = Vector2.ONE
		notebook_left_page.modulate.a = 1.0
		notebook_right_page.modulate.a = 1.0

func _active_aquarium_id() -> String:
	if aquarium_index.is_empty():
		return ""
	return str(aquarium_index.get("active_id", ""))

func _create_clear_aquarium() -> void:
	var name := tank_name_edit.text.strip_edges() if tank_name_edit else "Clear Aquarium"
	if name == "":
		name = "Clear Aquarium"
	var system := "freshwater"
	if tank_system_select and tank_system_select.selected >= 0:
		system = str(tank_system_select.get_item_metadata(tank_system_select.selected))
	var litres := 60.0
	if tank_litres_spin:
		litres = float(tank_litres_spin.value)
	_write_command({"action": "create_aquarium", "name": name, "system": system, "gross_litres": litres})
	if tool_label:
		tool_label.text = "Creating %s. It will appear in the aquarium selector in a moment." % name

func _refresh_species_options() -> void:
	if not species_select:
		return
	var current_system := str(state.get("water", {}).get("system", "freshwater"))
	var selected_id := ""
	if species_select.item_count > 0 and species_select.selected >= 0:
		selected_id = str(species_select.get_item_metadata(species_select.selected))
	species_select.clear()
	var selected_index := -1
	for id in species.keys():
		var spec: Dictionary = species[id]
		if str(spec.get("water_type", "freshwater")) != current_system:
			continue
		species_select.add_item("%s (%s)" % [spec.get("common_name", id), spec.get("swim_zone", "middle")])
		species_select.set_item_metadata(species_select.item_count - 1, id)
		if id == selected_id:
			selected_index = species_select.item_count - 1
	if selected_index >= 0:
		species_select.select(selected_index)
	elif species_select.item_count > 0:
		species_select.select(0)
	_refresh_research_card()

func _refresh_research_card() -> void:
	if not research_label or not notebook_right_label:
		return
	if not species_select or species_select.item_count <= 0 or species_select.selected < 0:
		_set_notebook_pages("No compatible species available for this water system.", "Switch aquarium type or add more species data later.")
		return
	var id := str(species_select.get_item_metadata(species_select.selected))
	var spec: Dictionary = species.get(id, {})
	if spec.is_empty():
		_set_notebook_pages("Select an animal to see care research.", "The journal updates from the current aquarium state.")
		return
	var aquarium = state.get("aquarium", {})
	var water = state.get("water", {})
	var equipment = state.get("equipment", {})
	var maturity = state.get("maturity", {})
	var chemistry = state.get("chemistry", {})
	var stability = state.get("stability", {})
	var biology = state.get("biology", {})
	var food = state.get("food", {})
	var residue = state.get("action_residue", {})
	var algae_ecology = state.get("algae_ecology", {})
	var disease_ecology = state.get("disease_ecology", {})
	var maintenance = state.get("maintenance", {})
	var maintenance_ecology = state.get("maintenance_ecology", {})
	var symptoms = state.get("symptoms", {})
	var summary = state.get("summary", {})
	var current_litres := float(aquarium.get("effective_litres", 0.0))
	var min_litres := float(spec.get("minimum_litres", 0.0))
	var min_length := float(spec.get("minimum_tank_length_cm", 0.0))
	var length := float(aquarium.get("length_cm", 0.0))
	var group := int(spec.get("minimum_group", 1))
	var preferred := int(spec.get("preferred_group", group))
	var status := "Tank fit looks possible" if current_litres >= min_litres and length >= min_length else "This tank is probably too small"
	var left: Array[String] = []
	var right: Array[String] = []
	left.append("FIELD NOTE - %s" % str(spec.get("common_name", id)).to_upper())
	left.append("%s" % spec.get("scientific_name", "unknown"))
	left.append("")
	left.append("Tank verdict: %s." % status)
	left.append("Needs: %.0f L usable water, %.0f cm swimming length, minimum group %d, preferred group %d." % [min_litres, min_length, group, preferred])
	left.append("Adult size %.1f cm, lifespan about %.0f years, main layer: %s." % [
		float(spec.get("adult_cm", 0.0)),
		float(spec.get("lifespan_years", 0.0)),
		str(spec.get("swim_zone", "middle"))
	])
	left.append("")
	left.append("Comfort window")
	left.append("Temperature %.0f-%.0f C, pH %.1f-%.1f, GH %.0f-%.0f dGH. Nitrate starts worrying near %.0f mg/L." % [
		float(spec.get("temperature_c", {}).get("ideal", [0, 0])[0]),
		float(spec.get("temperature_c", {}).get("ideal", [0, 0])[1]),
		float(spec.get("ph", {}).get("ideal", [0, 0])[0]),
		float(spec.get("ph", {}).get("ideal", [0, 0])[1]),
		float(spec.get("gh_dgh", {}).get("ideal", [0, 0])[0]),
		float(spec.get("gh_dgh", {}).get("ideal", [0, 0])[1]),
		float(spec.get("nitrate_warning_mg_l", 20.0))
	])
	left.append("Needs oxygen above %.1f mg/L. Social style: %s." % [
		float(spec.get("oxygen_min_mg_l", 5.0)),
		str(spec.get("social", "community")).replace("_", " ")
	])
	left.append("")
	if str(water.get("system", "freshwater")) != str(spec.get("water_type", "freshwater")):
		left.append("Margin warning: wrong water system for this animal.")
	left.append(_compatibility_hint(id, spec))
	if spec.has("care_notes"):
		left.append("Keeper note: %s" % str(spec["care_notes"]))
	if spec.has("sources"):
		left.append("Source bookmarks: %s" % _source_summary(spec.get("sources", [])))
	left.append("")
	left.append("Current fit")
	left.append("This aquarium has %.0f L usable water and %.0f cm swimming length." % [current_litres, length])
	left.append("Current water: %.1f C, pH %.2f, GH %.1f, KH %.1f, O2 %.1f, NO3 %.1f, PO4 %.2f." % [
		float(water.get("temperature_c", 0.0)),
		float(water.get("ph", 0.0)),
		float(water.get("gh_dgh", 0.0)),
		float(water.get("kh_dkh", water.get("alkalinity_dkh", 0.0))),
		float(water.get("oxygen_mg_l", 0.0)),
		float(water.get("nitrate_mg_l", 0.0)),
		float(water.get("phosphate_mg_l", 0.0))
	])

	right.append("AQUARIUM SYSTEM NOTES")
	right.append("Overall status: %s. Risks: %s." % [str(summary.get("status", "unknown")), ", ".join(summary.get("risks", [])) if summary.get("risks", []).size() > 0 else "none visible"])
	right.append("Stability %.0f%% after recent %s pressure. Active grazing %.0f%%, metabolic load %.2f." % [
		float(stability.get("stability_score", 1.0)) * 100.0,
		str(stability.get("latest_swing", "stable")),
		float(biology.get("grazing_pressure", 0.0)) * 100.0,
		float(biology.get("metabolic_load", 0.0))
	])
	right.append("Recent care residue: haze %.0f%%, plant bits %.0f%%, handling stress %.0f%%." % [
		(float(residue.get("suspended_debris", 0.0)) + float(residue.get("filter_biofilm_shed", 0.0))) * 100.0,
		float(residue.get("plant_fragments", 0.0)) * 100.0,
		float(residue.get("hands_in_tank_stress", 0.0)) * 100.0
	])
	right.append("")
	right.append("Nitrogen cycle")
	right.append("Ammonia and nitrite should stay at 0. Total ammonia becomes far more toxic as pH and temperature rise, because more of it is un-ionized NH3.")
	right.append("Current TAN %.3f, free NH3 %.4f, NO2 %.3f, NO3 %.1f mg/L." % [
		float(water.get("ammonia_mg_l", 0.0)),
		float(water.get("free_ammonia_mg_l", 0.0)),
		float(water.get("nitrite_mg_l", 0.0)),
		float(water.get("nitrate_mg_l", 0.0))
	])
	right.append("")
	right.append("Phosphate, silicate, algae")
	right.append("Food, decay, source water, and mulm raise phosphate. Silicate feeds brown diatom dust, especially in young tanks or with silicate-leaching rocks. Long light pushes green water and hair algae. Dead flow and organics can favor cyanobacteria.")
	right.append("Current PO4 %.2f, silicate %.2f, green water %.0f%%, diatoms %.0f%%, hair %.0f%%, cyano %.0f%%, black beard %.0f%%. Main driver: %s." % [
		float(water.get("phosphate_mg_l", 0.0)),
		float(water.get("silicate_mg_l", 0.0)),
		float(symptoms.get("green_water", 0.0)) * 100.0,
		float(symptoms.get("diatom_dust", 0.0)) * 100.0,
		float(symptoms.get("hair_algae", 0.0)) * 100.0,
		float(symptoms.get("cyanobacteria", 0.0)) * 100.0,
		float(symptoms.get("black_beard_algae", 0.0)) * 100.0,
		str(algae_ecology.get("last_driver", "balanced"))
	])
	right.append("")
	right.append("Scape effects")
	right.append("Wood releases tannins and usually softens/acidifies. Reef rock and some stones raise KH, GH, calcium, and pH slowly. Lava or dragon stone can add silicate. Plants pull nitrate/phosphate, add oxygen in light, consume oxygen at night, and add decay if they melt.")
	right.append("Cover %.0f%%, shade %.0f%%, tannins %.0f%%, soft-water pressure %.0f%%, KH release %.0f%%." % [
		float(aquarium.get("hiding_cover", 0.0)) * 100.0,
		float(aquarium.get("surface_shade", 0.0)) * 100.0,
		float(water.get("tannins", 0.0)) * 100.0,
		float(aquarium.get("soft_water", 0.0)) * 100.0,
		float(aquarium.get("kh_release", 0.0)) * 100.0
	])
	right.append("")
	right.append("Reef chemistry")
	right.append("Saltwater coral growth consumes alkalinity, calcium, magnesium, and trace elements. Dosing helps, but water changes are the gentler reset.")
	right.append("Alk %.1f dKH, calcium %.0f, magnesium %.0f, trace %.0f%%, salinity %.1f ppt." % [
		float(water.get("alkalinity_dkh", water.get("kh_dkh", 0.0))),
		float(water.get("calcium_mg_l", 0.0)),
		float(water.get("magnesium_mg_l", 0.0)),
		float(water.get("trace_elements", 0.0)) * 100.0,
		float(water.get("salinity_ppt", 0.0))
	])
	right.append("")
	right.append("Equipment and maturity")
	var filter = equipment.get("filter", {})
	var media = filter.get("media", {})
	var mechanical = media.get("mechanical", {})
	right.append("Filter flow %.0f%%, clog %.0f%%, channeling %.0f%%, bypass %.0f%%, slough risk %.0f%%. Main cause: %s." % [
		float(filter.get("effective_flow", filter.get("flow", 0.0))) * 100.0,
		float(mechanical.get("clog", 0.0)) * 100.0,
		float(mechanical.get("channeling", 0.0)) * 100.0,
		float(filter.get("bypass_risk", 0.0)) * 100.0,
		float(filter.get("biofilm_slough_risk", 0.0)) * 100.0,
		str(filter.get("last_flow_driver", "balanced flow"))
	])
	right.append("Mature biofilm %.0f%%, microfauna %.0f%%, mulm %.0f%%. Old tanks gain stability, but also trapped waste, biofilm shedding, and hypoxic pockets if ignored." % [
		float(maturity.get("biofilm", 0.0)) * 100.0,
		float(maturity.get("microfauna", 0.0)) * 100.0,
		float(maturity.get("mulm", 0.0)) * 100.0
	])
	var heater = equipment.get("heater", {})
	var light = equipment.get("light", {})
	var air = equipment.get("air_pump", {})
	right.append("Heater variance %.2f C, cycling %.0f%%, sticky thermostat %.0f%%, driver %s. Placement and room swings decide whether the set point is really stable." % [
		float(heater.get("temperature_variance_c", 0.0)),
		float(heater.get("cycle_stress", 0.0)) * 100.0,
		float(heater.get("thermostat_stickiness", 0.0)) * 100.0,
		str(heater.get("last_heat_driver", "stable"))
	])
	right.append("Light actual %.1fh, PAR %.0f%%, lens film %.0f%%, spectrum shift %.0f%%, driver %s. Dirty covers can starve plants before the light looks broken." % [
		float(light.get("actual_hours_per_day", light.get("hours_per_day", 0.0))),
		float(light.get("par_output", 0.0)) * 100.0,
		float(light.get("lens_film", 0.0)) * 100.0,
		float(light.get("spectrum_shift", 0.0)) * 100.0,
		str(light.get("last_light_driver", "fresh output"))
	])
	right.append("Air delivered %.0f%%, airline clog %.0f%%, check-valve risk %.0f%%, driver %s. Surface movement and real delivered air decide oxygen/CO2 exchange." % [
		float(air.get("effective_output", air.get("output", 0.0))) * 100.0,
		float(air.get("airline_clog", 0.0)) * 100.0,
		float(air.get("check_valve_risk", 0.0)) * 100.0,
		str(air.get("last_air_driver", "clear airline"))
	])
	var skimmer = equipment.get("protein_skimmer", {})
	var ato = equipment.get("auto_top_off", {})
	right.append("Skimmer export %.0f%%, neck %.0f%%, tuning drift %.0f%%, microbubbles %.0f%%. ATO sensor film %.0f%% and overfill risk %.0f%%." % [
		float(skimmer.get("effective_output", skimmer.get("output", 0.0))) * 100.0,
		float(skimmer.get("neck_fouling", 0.0)) * 100.0,
		float(skimmer.get("tuning_drift", 0.0)) * 100.0,
		float(skimmer.get("microbubble_leak", 0.0)) * 100.0,
		float(ato.get("sensor_film", 0.0)) * 100.0,
		float(ato.get("overfill_risk", 0.0)) * 100.0
	])
	right.append("Redox %.0f mV, dissolved organics %.2f, substrate hypoxia %.0f%%, buffer stability %.0f%%." % [
		float(water.get("redox_mv", 0.0)),
		float(water.get("dissolved_organics", 0.0)),
		float(maturity.get("substrate_hypoxia", 0.0)) * 100.0,
		float(chemistry.get("buffer_stability", 0.0)) * 100.0
	])
	right.append("Pathogen pressure: parasite %.0f%%, bacterial %.0f%%. These rise with stress, decay, crowding, dirty substrate, and dead animals." % [
		float(water.get("parasite_pressure", 0.0)) * 100.0,
		float(water.get("bacterial_pressure", 0.0)) * 100.0
	])
	right.append("Disease ecology: %s. Free swimmers %.0f%%, cysts %.0f%%, bacterial bloom %.0f%%, treatment %.0f%%, quarantined %d." % [
		str(disease_ecology.get("outbreak_stage", "quiet")),
		float(disease_ecology.get("free_swimming_parasites", 0.0)) * 100.0,
		float(disease_ecology.get("encysted_parasites", 0.0)) * 100.0,
		float(disease_ecology.get("bacterial_bloom", 0.0)) * 100.0,
		float(disease_ecology.get("treatment_strength", 0.0)) * 100.0,
		int(symptoms.get("quarantined_animals", 0))
	])
	var pages: Array = ["\n".join(left), "\n".join(right)]
	pages.append("COMPATIBILITY CHECKLIST\nSame water type matters first. Then compare adult size, minimum group, preferred group, swim layer, territoriality, fin nipping, predator mouth size, activity level, hiding needs, and nitrate tolerance.\n\nSchooling fish are not decoration: they need their group before mixed community ideas matter. Territorial fish need broken sight lines and space. Bottom fish need substrate and hiding routes. Long-finned fish dislike strong current and fin nippers.")
	pages.append("NITROGEN CYCLE\nFish waste and uneaten food become total ammonia, usually written TAN. Mature bacteria convert ammonia to nitrite, then nitrite to nitrate.\n\nThe toxic part is free un-ionized NH3. The same TAN is much more dangerous in warm alkaline water and less dangerous in cool acidic water. Nitrite also hurts oxygen transport.\n\nCurrent free ammonia fraction %.3f%%, toxicity index %.2f." % [float(chemistry.get("free_ammonia_fraction", 0.0)) * 100.0, float(water.get("nitrogen_toxicity_index", 0.0))])
	var safety = state.get("safety", {})
	pages.append("REAL TIME AND SURVIVAL\nAt normal speed, one real hour is one aquarium hour. Acute ammonia, nitrite, chlorine, oxygen loss, or severe acclimation shock can still become dangerous quickly. Social isolation, imperfect diet, ordinary disease pressure, and other chronic problems now build over days to weeks instead of killing healthy fish overnight.\n\nAn immature cycle is a warning, not invisible poison: fish are harmed when the immature filter allows ammonia or nitrite to rise. Larger tanks dilute livestock waste more effectively; small tanks concentrate it faster. Feed portions adapt to the living bioload and current hunger, but leftovers still decay.\n\nSafeguard readiness is %d%%. Fit the safety and outage kit for a lid, guarded intake, drip loops, protected-power plan, dedicated tools, spare conditioner, and battery aeration." % int(safety.get("readiness_score", 0)))
	pages.append("WATER CHANGES\nA water change dilutes ammonia, nitrite, nitrate, phosphate, organics, turbidity, surface film, and detritus.\n\nIt can also add whatever is in the source water: nitrate, phosphate, chlorine, chloramine, silicate, KH, GH, TDS, calcium, magnesium, salinity, and trace elements.\n\nLarge, fast, cold, hot, untreated, pH-mismatched, hardness-mismatched, or substrate-disturbing changes cause shock. Disturbing the bed can remove compacted waste, but it can also release mulm and organics.")
	pages.append("MAINTENANCE CHEMISTRY MEMORY\nA real tank remembers care. A large water change may test fine afterward but still leave animals dealing with source-water mismatch, conditioner residue, disturbed mulm, reduced biofilter margin, or chloramine-derived ammonia load.\n\nThe safest rhythm is small, matched, conditioned changes with the substrate cleaned in sections. Repeated big changes can create fatigue even when each one was meant to help.\n\nCurrent care style: %s. Last driver: %s. Change debt %.0f%%, mismatch %.0f%%, conditioner %.0f%%, substrate %.0f%%, biofilter %.0f%%, chloramine nitrogen %.0f%%." % [
		str(maintenance_ecology.get("last_care_style", "settled")),
		str(maintenance_ecology.get("last_mismatch_driver", "none")),
		float(maintenance_ecology.get("change_frequency_debt", 0.0)) * 100.0,
		float(maintenance_ecology.get("source_mismatch_debt", 0.0)) * 100.0,
		float(maintenance_ecology.get("conditioner_residue", 0.0)) * 100.0,
		float(maintenance_ecology.get("substrate_disturbance_debt", 0.0)) * 100.0,
		float(maintenance_ecology.get("biofilter_handling_debt", 0.0)) * 100.0,
		float(maintenance_ecology.get("chloramine_ammonia_debt", 0.0)) * 100.0
	])
	pages.append("STABILITY MEMORY\nReal aquariums do not reset biologically after one good test. The app remembers 24-hour temperature, pH, salinity, and TDS swings plus water-change shock debt.\n\nFish, plants, corals, disease pressure, and welfare react to this history. Stability recovers slowly with time, gentle maintenance, steady temperature, and small matched water changes.\n\nCurrent stability %.0f%%. 24h swings: %.2f C, %.2f pH, %.2f ppt salinity, %.0f TDS. Main pressure: %s." % [
		float(stability.get("stability_score", 1.0)) * 100.0,
		float(stability.get("temperature_swing_24h", 0.0)),
		float(stability.get("ph_swing_24h", 0.0)),
		float(stability.get("salinity_swing_24h", 0.0)),
		float(stability.get("tds_swing_24h", 0.0)),
		str(stability.get("latest_swing", "stable"))
	])
	pages.append("WOOD AND ROCKS\nWood does not make water alkaline. Driftwood releases tannins, darkens the water, and usually softens or acidifies slowly. Root driftwood is stronger; branch wood is moderate; manzanita is milder.\n\nReef/live rock and mineral stones can raise KH, calcium, hardness, and pH slowly. Lava rock and dragon stone can add silicate, which can feed brown diatom dust.\n\nCurrent tannins %.0f%%, soft-water pressure %.0f%%, KH release %.0f%%, silicate %.2f." % [float(water.get("tannins", 0.0)) * 100.0, float(aquarium.get("soft_water", 0.0)) * 100.0, float(aquarium.get("kh_release", 0.0)) * 100.0, float(water.get("silicate_mg_l", 0.0))])
	pages.append("SUBSTRATE\nFine sand looks natural and lets bottom fish forage, but deep sand can compact if neglected. Gravel is easy to clean but traps food. Planted soil feeds roots and can grow plants better, but adds maintenance load. Bare bottom is clean but bad for rooted plants.\n\nDeep compacted substrate with mulm can become hypoxic. Some denitrifying biofilm can reduce nitrate, but stagnant pockets also lower redox and can create dangerous reduced chemistry. Clean in sections.\n\nCurrent substrate: %s, %.1f cm. Compaction %.0f%%, hypoxia %.0f%%, anaerobic risk %.0f%%." % [str(aquarium.get("substrate", "unknown")).replace("_", " "), float(aquarium.get("substrate_depth_cm", 0.0)), float(maturity.get("substrate_compaction", 0.0)) * 100.0, float(maturity.get("substrate_hypoxia", 0.0)) * 100.0, float(maturity.get("anaerobic_pocket_risk", 0.0)) * 100.0])
	pages.append("PLANTS\nPlants use nitrate, phosphate, light, CO2, trace elements, and sometimes root nutrients. They add oxygen in the light and use oxygen at night.\n\nIf one resource is missing, extra of the others does not fix it. If conditions are wrong, plants melt; melt adds organics, ammonia, and phosphate.\n\nCurrent plant cover %.0f%%, shade %.0f%%, algae control %.0f%%, limiting factor: %s." % [float(aquarium.get("plant_cover", 0.0)) * 100.0, float(aquarium.get("surface_shade", 0.0)) * 100.0, float(aquarium.get("algae_control", 0.0)) * 100.0, str(chemistry.get("plant_limiting_factor", "balanced"))])
	var plant_items = []
	var scape_data = aquarium.get("scape", {})
	for plant in scape_data.get("plants", []):
		plant_items.append(plant)
	for obj in scape_data.get("objects", []):
		if str(obj.get("category", "")) == "plants":
			plant_items.append(obj)
	var root_sum: float = 0.0
	var reserve_sum: float = 0.0
	var melt_max: float = 0.0
	var smother_max: float = 0.0
	var plant_drivers = []
	for plant in plant_items:
		root_sum += float(plant.get("root_establishment", 0.0))
		reserve_sum += float(plant.get("nutrient_reserve", 0.0))
		melt_max = max(melt_max, float(plant.get("melt_debt", 0.0)))
		smother_max = max(smother_max, float(plant.get("algae_smothering", 0.0)))
		plant_drivers.append("%s: %s" % [str(plant.get("type", "plant")).replace("_", " "), str(plant.get("last_growth_driver", "settling"))])
	var plant_count: float = max(1.0, float(plant_items.size()))
	pages.append("PLANT MEMORY\nPlants now remember whether they are rooted, fed, shaded, smothered, or melting. Good substrate and stable water build root establishment. Light plus nitrate, phosphate, trace elements, and root access build reserves. Shade, algae, poor substrate, shocks, and low reserves create melt debt.\n\nCurrent average rooting %.0f%%, reserve %.0f%%, worst melt debt %.0f%%, worst algae smothering %.0f%%.\n\nDrivers:\n%s" % [
		root_sum / plant_count * 100.0,
		reserve_sum / plant_count * 100.0,
		melt_max * 100.0,
		smother_max * 100.0,
		"\n".join(plant_drivers.slice(0, 8)) if plant_drivers.size() > 0 else "No plants placed."
	])
	pages.append("ALGAE ECOLOGY\nAlgae is not one problem. Green water is suspended algae from light plus nutrients. Brown diatoms come from silicate and young tanks. Hair algae likes long light and available nitrate/phosphate. Cyanobacteria is a slimy mat favored by dead flow, organics, low redox, and imbalance. Black beard algae follows unstable CO2, old hardscape biofilm, and dead spots.\n\nScraping removes glass film and some diatoms but releases debris. Cleanup animals graze hair algae and diatoms slowly. Plants compete for nutrients, but melting plants can feed algae back.\n\nCurrent green water %.0f%%, brown diatoms %.0f%%, hair %.0f%%, cyanobacteria %.0f%%, black beard %.0f%%, glass film %.0f%%, nutrient memory %.0f%%, light memory %.0f%%, dead spots %.0f%%, main driver: %s." % [
		float(algae_ecology.get("green_water", 0.0)) * 100.0,
		float(algae_ecology.get("brown_diatoms", 0.0)) * 100.0,
		float(algae_ecology.get("hair_algae", 0.0)) * 100.0,
		float(algae_ecology.get("cyanobacteria", 0.0)) * 100.0,
		float(algae_ecology.get("black_beard_algae", 0.0)) * 100.0,
		float(algae_ecology.get("glass_film", 0.0)) * 100.0,
		float(algae_ecology.get("nutrient_memory", 0.0)) * 100.0,
		float(algae_ecology.get("light_memory", 0.0)) * 100.0,
		float(algae_ecology.get("flow_dead_spots", 0.0)) * 100.0,
		str(algae_ecology.get("last_driver", "balanced"))
	])
	pages.append("CORALS AND REEF CHEMISTRY\nSaltwater stability depends on salinity, alkalinity, calcium, magnesium, temperature, flow, light, nitrate, phosphate, and trace elements.\n\nCoral growth consumes alkalinity, calcium, magnesium, and trace reserves. Evaporation raises salinity because water leaves but salt stays. Top-off restores level; mineral dosing restores depleted reserves.\n\nCurrent salinity %.1f ppt, alkalinity %.1f dKH, calcium %.0f, magnesium %.0f, limiting factor: %s." % [float(water.get("salinity_ppt", 0.0)), float(water.get("alkalinity_dkh", water.get("kh_dkh", 0.0))), float(water.get("calcium_mg_l", 0.0)), float(water.get("magnesium_mg_l", 0.0)), str(chemistry.get("coral_limiting_factor", "balanced"))])
	var coral_items = []
	for coral in scape_data.get("corals", []):
		coral_items.append(coral)
	for obj in scape_data.get("objects", []):
		if str(obj.get("category", "")) == "corals":
			coral_items.append(obj)
	var polyp_sum: float = 0.0
	var tissue_sum: float = 0.0
	var bleach_max: float = 0.0
	var flow_sum: float = 0.0
	var coral_drivers = []
	for coral in coral_items:
		polyp_sum += float(coral.get("polyp_extension", 0.0))
		tissue_sum += float(coral.get("tissue_reserve", 0.0))
		bleach_max = max(bleach_max, float(coral.get("bleaching_debt", 0.0)))
		flow_sum += float(coral.get("flow_comfort", 0.0))
		coral_drivers.append("%s: %s" % [str(coral.get("type", "coral")).replace("_", " "), str(coral.get("last_stress_driver", "settling"))])
	var coral_count: float = max(1.0, float(coral_items.size()))
	pages.append("CORAL POLYP MEMORY\nCorals now react with polyp extension, tissue reserve, flow comfort, feeding response, and bleaching debt. Good light, moderate flow, stable reef minerals, and plankton feeding help tissue reserves. Bad flow, low alkalinity/calcium/magnesium, unstable salinity, excess nutrients, or weak light retract polyps and build bleaching debt.\n\nCurrent polyp extension %.0f%%, tissue reserve %.0f%%, flow comfort %.0f%%, worst bleaching debt %.0f%%.\n\nDrivers:\n%s" % [
		polyp_sum / coral_count * 100.0,
		tissue_sum / coral_count * 100.0,
		flow_sum / coral_count * 100.0,
		bleach_max * 100.0,
		"\n".join(coral_drivers.slice(0, 8)) if coral_drivers.size() > 0 else "No corals placed."
	])
	pages.append("FEEDING AND WASTE\nFood helps body condition, energy, breeding condition, and confidence only when the animal can actually use it. Flakes linger near the surface, wafers reach bottom fish, algae foods suit grazers, frozen foods are rich but dirtier, and reef blends add planktonic nutrition plus nutrients.\n\nWrong foods are not harmless. Poor diet fit leaves shy or specialized animals hungry, lowers digestion quality, drains vitamin/fiber reserves, adds fecal waste, increases ammonia and phosphate pressure, clouds water, and feeds bacteria.\n\nLast food: %s. Available %.2f, decaying %.2f, consumed %.2f. Protein %.0f%%, fat %.0f%%, fiber %.0f%%, plant matter %.0f%%, vitamins %.0f%%, minerals %.0f%%, digestibility %.0f%%, sinking %.0f%%, spoilage %.0f%%, clouding %.0f%%, phosphate pressure %.0f%%. Nutrition quality %.0f%%, diet mismatch %.0f%%, digestive waste %.0f%%." % [
		str(food.get("last_type", "community_flake")).replace("_", " "),
		float(food.get("available", 0.0)),
		float(food.get("decaying", 0.0)),
		float(food.get("last_consumed", 0.0)),
		float(food.get("protein", 0.42)) * 100.0,
		float(food.get("fat", 0.18)) * 100.0,
		float(food.get("fiber", 0.16)) * 100.0,
		float(food.get("plant", 0.18)) * 100.0,
		float(food.get("vitamin", 0.62)) * 100.0,
		float(food.get("mineral", 0.46)) * 100.0,
		float(food.get("digestibility", 0.72)) * 100.0,
		float(food.get("sinking", 0.35)) * 100.0,
		float(food.get("spoilage", 0.74)) * 100.0,
		float(food.get("clouding", 0.9)) * 100.0,
		float(food.get("phosphate_factor", 1.0)) * 100.0,
		float(food.get("nutrition_quality_ewma", 0.72)) * 100.0,
		float(food.get("diet_mismatch_ewma", 0.0)) * 100.0,
		float(symptoms.get("digestive_waste", 0.0)) * 100.0
	])
	var behavior_samples := []
	for animal in state.get("animals", []):
		if not bool(animal.get("alive", true)):
			continue
		behavior_samples.append("%s: %s\n  intent: %s because %s - confidence %.0f%%, school %.0f%%, territory %.0f%%, rest %.0f%%" % [
			str(animal.get("name", "animal")),
			str(animal.get("behavior", "observing")),
			str(animal.get("behavior_intent", "settling")),
			str(animal.get("behavior_trigger", "current conditions")),
			float(animal.get("confidence", 0.0)) * 100.0,
			float(animal.get("school_cohesion", 0.0)) * 100.0,
			float(animal.get("territory_pressure", 0.0)) * 100.0,
			float(animal.get("rest_quality", 0.0)) * 100.0
		])
	pages.append("FISH ROUTINES AND PERSONALITY\nFish are not just water-test meters. Each animal keeps confidence, fear memory, feeding opportunity, rest quality, school cohesion, territory pressure, a decision timer, and a short memory of recent choices.\n\nThe rule-based behavior brain weighs health, stress, hunger, water flow, light phase, cover, open space, social group, feeding rank, species role, curiosity, boldness, and current conditions. It then chooses a short-lived intent such as regrouping, following, scouting, grazing, sifting, current riding, cover checking, surface patrol, territory patrol, resting, or exploration. These choices are bounded and non-lethal: emergencies and welfare still come from the simulation itself, not random behavior.\n\nCurrent observations:\n%s" % ("\n".join(behavior_samples.slice(0, 8)) if behavior_samples.size() > 0 else "No animals in this aquarium yet."))
	pages.append("CLEANUP CREWS\nShrimp, otocinclus, plecos, blennies, and cleaner shrimp do useful work, but they are not magic filters. They graze algae, biofilm, detritus, and leftovers, then turn some of that into ordinary animal waste.\n\nThey work best when healthy and hungry. Stress, bad water, wrong salinity, or poor group sizes reduce grazing.\n\nCurrent grazing pressure %.0f%%, recent cleanup export %.3f, metabolic load %.2f." % [
		float(biology.get("grazing_pressure", 0.0)) * 100.0,
		float(biology.get("cleanup_export", 0.0)),
		float(biology.get("metabolic_load", 0.0))
	])
	var filter_state = equipment.get("filter", {})
	var media_state = filter_state.get("media", {})
	var mechanical_state = media_state.get("mechanical", {})
	var chemical_state = media_state.get("chemical", {})
	var heater_state = equipment.get("heater", {})
	var light_state = equipment.get("light", {})
	var skimmer_state = equipment.get("protein_skimmer", {})
	pages.append("EQUIPMENT\nThe filter handles mechanical trapping, biological conversion, and optional chemical polishing. Clogging reduces flow. Channeling means water bypasses media, so the filter can run while filtering badly.\n\nCarbon removes organics and tint. Phosphate media reduces phosphate but depletes. Service age matters because exhausted media and dirty mechanics slowly stop doing useful work.\n\nCurrent flow %.0f%%, clog %.0f%%, channeling %.0f%%, carbon %.0f%%, PO4 media %.0f%%, filter service %.0f h, media age %.0f d." % [float(filter_state.get("effective_flow", filter_state.get("flow", 0.0))) * 100.0, float(mechanical_state.get("clog", 0.0)) * 100.0, float(mechanical_state.get("channeling", 0.0)) * 100.0, float(chemical_state.get("carbon_remaining", 0.0)) * 100.0, float(chemical_state.get("phosphate_remover_remaining", 0.0)) * 100.0, float(filter_state.get("service_hours", 0.0)), float(chemical_state.get("media_age_days", 0.0))])
	pages.append("GAS, LIGHT, TEMPERATURE\nOxygen depends on surface agitation, air output, plant day/night rhythm, temperature, salinity, bioload, organics, and surface film. Warm or salty water holds less oxygen.\n\nLights age before they visibly fail: useful spectrum and PAR drop, so plants or corals can stall even when the lamp still turns on. Heaters also drift from their set point as they age.\n\nCurrent O2 %.1f, CO2 %.1f, surface film %.0f%%, light %.1f h, effective spectrum %.0f%%, PAR %.0f%%, lamp age %.0f d, heater offset %.2f C, skimmer fouling %.0f%%." % [
		float(water.get("oxygen_mg_l", 0.0)),
		float(water.get("co2_mg_l", 0.0)),
		float(water.get("surface_film", 0.0)) * 100.0,
		float(light_state.get("hours_per_day", 0.0)),
		float(light_state.get("effective_spectrum", light_state.get("plant_spectrum", 0.82))) * 100.0,
		float(light_state.get("par_output", light_state.get("health", 1.0))) * 100.0,
		float(light_state.get("lamp_age_days", 0.0)),
		float(heater_state.get("calibration_offset_c", 0.0)),
		float(skimmer_state.get("neck_fouling", 0.0)) * 100.0
	])
	pages.append("REDOX AND ORGANICS\nRedox/ORP is a rough sign of the water's oxidizing capacity. It falls when oxygen debt, dissolved organics, stagnant substrate, surface film, and bacterial pressure rise. It is not a magic score, but a low value means the tank is carrying hidden biological load.\n\nCarbon, skimming, water changes, flow, aeration, less feeding, and removing decay improve it slowly.\n\nCurrent ORP %.0f mV, dissolved organics %.2f, oxygen debt %.0f%%, trend: %s." % [float(water.get("redox_mv", 0.0)), float(water.get("dissolved_organics", 0.0)), float(chemistry.get("oxygen_debt", 0.0)) * 100.0, str(chemistry.get("redox_trend", "stable"))])
	pages.append("DISEASE AND STRESS\nDisease follows conditions. Stress, injury, dirty water, bad acclimation, ammonia, nitrite, low oxygen, high CO2, salinity drift, parasite pressure, bacterial pressure, and weak immunity all matter.\n\nThe tank now tracks a simple pathogen life cycle: carriers shed parasites, free swimmers can infect fish, cyst stages wait in the environment, and dirty water can bloom bacteria. Quarantine lowers display shedding. Treatment lowers pathogens but also disturbs oxygen, microfauna, and biofilter margins.\n\nFish track body condition, gill condition, fin condition, parasite load, immune condition, immune memory, fear memory, hunger, social satisfaction, and stress.\n\nCurrent stage %s, free swimmers %.0f%%, cysts %.0f%%, bacterial bloom %.0f%%, parasite pressure %.0f%%, bacterial pressure %.0f%%, visible disease %.0f%%, quarantined %d." % [
		str(disease_ecology.get("outbreak_stage", "quiet")),
		float(disease_ecology.get("free_swimming_parasites", 0.0)) * 100.0,
		float(disease_ecology.get("encysted_parasites", 0.0)) * 100.0,
		float(disease_ecology.get("bacterial_bloom", 0.0)) * 100.0,
		float(water.get("parasite_pressure", 0.0)) * 100.0,
		float(water.get("bacterial_pressure", 0.0)) * 100.0,
		float(symptoms.get("visible_disease", 0.0)) * 100.0,
		int(symptoms.get("quarantined_animals", 0))
	])
	pages.append("TANK MATURITY\nA new tank is fragile. A mature tank develops biofilm, infusoria, copepods, rooted plants, mulm, stable bacteria, and small visual aging. That tiny life can feed fry and small fish, polish organics, and make the aquarium feel settled.\n\nIt can also go wrong. Too much leftover food can bloom infusoria, cloud the water, raise bacterial pressure, and fuel pest snails. A very old or neglected tank can develop low KH, nitrate buildup, compacted substrate, and old-tank pressure.\n\nCurrent seasoning %.0f%%, biofilm %.0f%%, microfauna %.0f%%, infusoria %.0f%%, copepods %.0f%%, pest snails %.0f%%, bloom %.0f%%, mulm %.0f%%, old-tank risk %.0f%%." % [
		float(maturity.get("seasoning", 0.0)) * 100.0,
		float(maturity.get("biofilm", 0.0)) * 100.0,
		float(maturity.get("microfauna", 0.0)) * 100.0,
		float(maturity.get("infusoria", 0.0)) * 100.0,
		float(maturity.get("copepods", 0.0)) * 100.0,
		float(maturity.get("pest_snails", 0.0)) * 100.0,
		float(maturity.get("microfauna_bloom", 0.0)) * 100.0,
		float(maturity.get("mulm", 0.0)) * 100.0,
		float(maturity.get("old_tank_risk", 0.0)) * 100.0
	])
	pages.append("MAINTENANCE ACTIONS\nTest water: produces realistic kit readings.\nFeed: helps animals but can become waste.\nRemove leftovers: stops food before it mineralizes.\nScrape: clears glass but releases some film.\nTrim: prevents overgrowth and melt.\nTop off: restores evaporated water and lowers concentrated TDS/salinity.\nRefresh media: restores flow and reduces clog/channeling.\nDose minerals: replenishes KH/GH or reef alkalinity/calcium/magnesium/trace reserves.")
	pages.append("CARE RESIDUE\nMaintenance is helpful, but it is not invisible. Feeding can dust the water with fines. Water changes and siphons suspend mulm. Scraping releases algae film. Trimming leaves plant fragments. Filter service can shed biofilm dust. Testing leaves tiny reagent traces. Hands and tools can briefly scare shy fish.\n\nGood care clears gradually through flow, filtration, time, and restraint. Too many actions at once can make a clean tank feel disturbed.\n\nCurrent last action: %s. Suspended debris %.0f%%, plant fragments %.0f%%, filter dust %.0f%%, reagent trace %.0f%%, handling stress %.0f%%." % [
		str(residue.get("last_action", "none")),
		float(residue.get("suspended_debris", 0.0)) * 100.0,
		float(residue.get("plant_fragments", 0.0)) * 100.0,
		float(residue.get("filter_biofilm_shed", 0.0)) * 100.0,
		float(residue.get("reagent_trace", 0.0)) * 100.0,
		float(residue.get("hands_in_tank_stress", 0.0)) * 100.0
	])
	var event_lines: Array[String] = ["CURRENT OBSERVATIONS", "Cloudiness %.0f%%, green water %.0f%%, glass algae %.0f%%, diatoms %.0f%%, hair %.0f%%, cyano %.0f%%." % [float(symptoms.get("cloudiness", 0.0)) * 100.0, float(symptoms.get("green_water", 0.0)) * 100.0, float(symptoms.get("glass_algae", 0.0)) * 100.0, float(symptoms.get("diatom_dust", 0.0)) * 100.0, float(symptoms.get("hair_algae", 0.0)) * 100.0, float(symptoms.get("cyanobacteria", 0.0)) * 100.0], "Feeding: nutrition stress %.0f%%, digestive waste %.0f%%, diet mismatch %.0f%%." % [float(symptoms.get("nutrition_stress", 0.0)) * 100.0, float(symptoms.get("digestive_waste", 0.0)) * 100.0, float(food.get("diet_mismatch_ewma", 0.0)) * 100.0], "Maintenance: %s. Care memory %.0f%%." % [("ok" if maintenance.get("issues", []).is_empty() else str(maintenance.get("issues", [])[0].get("title", "attention needed"))), float(symptoms.get("care_instability", 0.0)) * 100.0], "", "Recent events:"]
	for event_item in state.get("events", []).slice(0, 5):
		event_lines.append("- %s: %s" % [str(event_item.get("severity", "info")), str(event_item.get("title", "event"))])
	pages.append("\n".join(event_lines))
	if spec.has("sources"):
		pages.append("SOURCE BOOKMARKS\n%s" % _source_summary(spec.get("sources", [])))
	var ledger_pages := _tank_ledger_pages()
	pages.append(ledger_pages[0])
	pages.append(ledger_pages[1])

	var page_titles: Array[String] = []
	var page_sketches: Array[String] = []
	for page in pages:
		var page_title := str(page).get_slice("\n", 0).strip_edges()
		page_titles.append(page_title.capitalize())
		page_sketches.append(_journal_sketch_key(page_title, id))

	var all_species_ids: Array = species.keys()
	all_species_ids.sort()
	var freshwater_names: Array[String] = []
	var saltwater_names: Array[String] = []
	for species_id_value in all_species_ids:
		var agenda_spec: Dictionary = species.get(species_id_value, {})
		var agenda_name := str(agenda_spec.get("common_name", species_id_value))
		if str(agenda_spec.get("water_type", "freshwater")) == "saltwater":
			saltwater_names.append(agenda_name)
		else:
			freshwater_names.append(agenda_name)
	var agenda_page := "KEEPER'S FIELD GUIDE AGENDA\nEvery animal in the Living Waters library is recorded here, whether or not it is stocked or compatible with the active aquarium. Use the page menu below to jump straight to a species.\n\nFRESHWATER (%d)\n%s\n\nMARINE (%d)\n%s\n\nThe stocking picker remains filtered for safety; this journal does not." % [freshwater_names.size(), "  ·  ".join(freshwater_names), saltwater_names.size(), "  ·  ".join(saltwater_names)]
	pages.insert(0, agenda_page)
	page_titles.insert(0, "Keeper's field guide agenda")
	page_sketches.insert(0, "agenda")
	for species_id_value in all_species_ids:
		var guide_id := str(species_id_value)
		var guide_spec: Dictionary = species.get(guide_id, {})
		pages.append(_species_agenda_entry(guide_id, guide_spec, aquarium, water))
		page_titles.append("Species · %s" % str(guide_spec.get("common_name", guide_id)))
		page_sketches.append("fish_" + guide_id)
	_set_notebook_entries(pages, page_titles, page_sketches)

func _tank_ledger_pages() -> Array[String]:
	var water: Dictionary = state.get("water", {})
	var equipment: Dictionary = state.get("equipment", {})
	var filter: Dictionary = equipment.get("filter", {})
	var media: Dictionary = filter.get("media", {})
	var mechanical: Dictionary = media.get("mechanical", {})
	var heater: Dictionary = equipment.get("heater", {})
	var light: Dictionary = equipment.get("light", {})
	var air: Dictionary = equipment.get("air_pump", {})
	var skimmer: Dictionary = equipment.get("protein_skimmer", {})
	var ato: Dictionary = equipment.get("auto_top_off", {})
	var cycle: Dictionary = state.get("cycle", {})
	var clock: Dictionary = state.get("clock", {})
	var planning: Dictionary = state.get("planning", {})
	var safety: Dictionary = state.get("safety", {})
	var maintenance: Dictionary = state.get("maintenance", {})
	var maintenance_ecology: Dictionary = state.get("maintenance_ecology", {})
	var randomness: Dictionary = state.get("randomness", {})
	var maturity: Dictionary = state.get("maturity", {})
	var stability: Dictionary = state.get("stability", {})
	var disease_ecology: Dictionary = state.get("disease_ecology", {})
	var local_hour := float(clock.get("local_hour", 0.0))
	var readings: Array[String] = ["TANK READINGS", "This is the live aquarium ledger formerly shown in the Journal tab. It follows the selected aquarium, not the selected species.", ""]
	for key in ["temperature_c", "ph", "kh_dkh", "alkalinity_dkh", "calcium_mg_l", "magnesium_mg_l", "trace_elements", "silicate_mg_l", "tds_mg_l", "salinity_ppt", "water_level", "oxygen_mg_l", "co2_mg_l", "ammonia_mg_l", "nitrite_mg_l", "nitrate_mg_l", "phosphate_mg_l", "chlorine_mg_l", "chloramine_mg_l", "surface_film", "detritus", "parasite_pressure", "bacterial_pressure"]:
		readings.append(_format_water(str(key), float(water.get(key, 0.0))))
	readings.append("")
	readings.append("Equipment: filter %.0f%% / clog %.0f%% / bypass %.0f%% / driver %s." % [float(filter.get("effective_flow", filter.get("flow", 0.0))) * 100.0, float(mechanical.get("clog", 0.0)) * 100.0, float(filter.get("bypass_risk", 0.0)) * 100.0, str(filter.get("last_flow_driver", "balanced flow"))])
	readings.append("Heater %.1f C, variance %.2f C, driver %s. Light %.1fh, PAR %.0f%%, lens film %.0f%%." % [float(heater.get("target_c", water.get("temperature_c", 24.0))), float(heater.get("temperature_variance_c", 0.0)), str(heater.get("last_heat_driver", "stable")), float(light.get("actual_hours_per_day", light.get("hours_per_day", 8.0))) if bool(light.get("enabled", true)) else 0.0, float(light.get("par_output", light.get("health", 1.0))) * 100.0, float(light.get("lens_film", 0.0)) * 100.0])
	readings.append("Air %.0f%% delivered, airline clog %.0f%%. Skimmer %.0f%%, tuning drift %.0f%%. ATO %s, sensor film %.0f%%." % [float(air.get("effective_output", air.get("output", 0.0))) * 100.0 if bool(air.get("enabled", true)) else 0.0, float(air.get("airline_clog", 0.0)) * 100.0, float(skimmer.get("effective_output", skimmer.get("output", 0.0))) * 100.0 if bool(skimmer.get("enabled", false)) else 0.0, float(skimmer.get("tuning_drift", 0.0)) * 100.0, "on" if bool(ato.get("enabled", false)) else "off", float(ato.get("sensor_film", 0.0)) * 100.0])
	var cycle_page: Array[String] = ["RECENT TIMELINE", "This is the live status and event history formerly shown in the Journal tab.", "", "Cycle: %s — animals %s — day %.0f — %s %.0f:%02d — %s." % [str(cycle.get("stage", "unknown")), "ready" if bool(cycle.get("ready_for_animals", false)) else "not ready", float(cycle.get("days_running", 0.0)), str(clock.get("day_phase", "day")), int(floor(local_hour)), int(fposmod(local_hour, 1.0) * 60.0), "lights on" if bool(clock.get("lights_on", false)) else "lights off"], "Planning: %.0f kg estimated, risk %d, safeguards %d%%." % [float(planning.get("estimated_total_weight_kg", 0.0)), int(planning.get("risk_score", 0)), int(safety.get("readiness_score", 0))], "Maintenance: %s. Care memory driver: %s." % ["ok" if maintenance.get("issues", []).is_empty() else str(maintenance.get("issues", [])[0].get("title", "attention needed")), str(maintenance_ecology.get("last_mismatch_driver", "settled"))], "Variability %.0f%%; stability %.0f%% (%s)." % [float(randomness.get("noise", 0.12)) * 100.0, float(stability.get("stability_score", 1.0)) * 100.0, str(stability.get("latest_swing", "stable"))], "Seasoned %.0f%%, mulm %.0f%%, old-tank risk %.0f%%, tiny life %.0f%%, pest snails %.0f%%." % [float(maturity.get("seasoning", 0.0)) * 100.0, float(maturity.get("mulm", 0.0)) * 100.0, float(maturity.get("old_tank_risk", 0.0)) * 100.0, (float(maturity.get("infusoria", 0.0)) * 0.42 + float(maturity.get("copepods", 0.0)) * 0.58) * 100.0, float(maturity.get("pest_snails", 0.0)) * 100.0], "Disease ecology: %s." % str(disease_ecology.get("outbreak_stage", "quiet")), "", "Recent events:"]
	for item in state.get("events", []).slice(0, 12):
		cycle_page.append("- %s: %s" % [str(item.get("severity", "info")).capitalize(), str(item.get("title", "Event"))])
	return ["\n".join(readings), "\n".join(cycle_page)]

func _set_notebook_pages(left: String, right: String) -> void:
	_set_notebook_entries([left, right])

func _set_notebook_entries(pages: Array, titles: Array = [], sketches: Array = []) -> void:
	notebook_pages = pages.duplicate()
	if notebook_pages.is_empty():
		notebook_pages = ["No journal pages available."]
	var next_titles: Array[String] = []
	var next_sketches: Array[String] = []
	for index in range(notebook_pages.size()):
		var derived_title := str(notebook_pages[index]).get_slice("\n", 0).strip_edges().capitalize()
		next_titles.append(str(titles[index]) if index < titles.size() else derived_title)
		next_sketches.append(str(sketches[index]) if index < sketches.size() else "cycle")
	var rebuild_index := next_titles != notebook_page_titles
	notebook_page_titles = next_titles
	notebook_page_sketches = next_sketches
	if notebook_page_index >= notebook_pages.size():
		notebook_page_index = max(0, notebook_pages.size() - 1)
	if notebook_page_index % 2 != 0:
		notebook_page_index -= 1
	if rebuild_index:
		_refresh_notebook_index()
	_render_notebook_pages(false)

func _turn_notebook(delta: int) -> void:
	if notebook_pages.is_empty():
		return
	var next_index: int = clampi(notebook_page_index + delta, 0, max(0, notebook_pages.size() - 1))
	if next_index % 2 != 0:
		next_index -= 1
	if next_index == notebook_page_index:
		return
	notebook_turn_direction = 1 if next_index > notebook_page_index else -1
	notebook_page_index = next_index
	notebook_turn_amount = 1.0
	_render_notebook_pages(true)

func _jump_notebook_to(item_index: int) -> void:
	if notebook_pages.is_empty():
		return
	if not notebook_index_select or item_index < 0 or item_index >= notebook_index_select.item_count:
		return
	var selected_page := int(notebook_index_select.get_item_metadata(item_index))
	var next_index: int = clampi(selected_page - (selected_page % 2), 0, max(0, notebook_pages.size() - 1))
	if next_index == notebook_page_index:
		_render_notebook_pages(false)
		return
	notebook_turn_direction = 1 if next_index > notebook_page_index else -1
	notebook_page_index = next_index
	notebook_turn_amount = 1.0
	_render_notebook_pages(true)

func _refresh_notebook_index() -> void:
	if not notebook_index_select:
		return
	notebook_index_select.clear()
	for index in range(notebook_page_titles.size()):
		notebook_index_select.add_item("%02d · %s" % [index + 1, notebook_page_titles[index]])
		notebook_index_select.set_item_metadata(index, index)

func _render_notebook_pages(reset_scroll: bool = false) -> void:
	var left_index := notebook_page_index
	var right_index := notebook_page_index + 1
	if research_label:
		research_label.text = str(notebook_pages[left_index]) if left_index < notebook_pages.size() else ""
	if notebook_right_label:
		notebook_right_label.text = str(notebook_pages[right_index]) if right_index < notebook_pages.size() else ""
	if notebook_left_sketch:
		var left_key := notebook_page_sketches[left_index] if left_index < notebook_page_sketches.size() else "cycle"
		notebook_left_sketch.texture = journal_sketch_textures.get(left_key, null)
		_layout_notebook_sketch(notebook_left_sketch, str(notebook_pages[left_index]) if left_index < notebook_pages.size() else "")
	if notebook_right_sketch:
		var right_key := notebook_page_sketches[right_index] if right_index < notebook_page_sketches.size() else "cycle"
		notebook_right_sketch.texture = journal_sketch_textures.get(right_key, null) if right_index < notebook_pages.size() else null
		_layout_notebook_sketch(notebook_right_sketch, str(notebook_pages[right_index]) if right_index < notebook_pages.size() else "")
	if notebook_left_page_label:
		notebook_left_page_label.text = "Page %d of %d  ·  %s" % [left_index + 1, notebook_pages.size(), notebook_page_titles[left_index]]
	if notebook_right_page_label:
		notebook_right_page_label.text = "Page %d of %d  ·  %s" % [right_index + 1, notebook_pages.size(), notebook_page_titles[right_index]] if right_index < notebook_pages.size() else ""
	if notebook_prev_button:
		notebook_prev_button.disabled = left_index <= 0
	if notebook_next_button:
		notebook_next_button.disabled = right_index >= notebook_pages.size() - 1
	if notebook_index_select:
		var target_page: int = mini(left_index, notebook_index_select.item_count - 1)
		if target_page >= 0:
			notebook_index_select.select(target_page)
	if reset_scroll:
		var left_scroll: ScrollContainer = research_label.get_parent().get_parent() as ScrollContainer if research_label else null
		var right_scroll: ScrollContainer = notebook_right_label.get_parent().get_parent() as ScrollContainer if notebook_right_label else null
		if left_scroll:
			left_scroll.scroll_vertical = 0
		if right_scroll:
			right_scroll.scroll_vertical = 0

func _layout_notebook_sketch(sketch: TextureRect, page_text: String) -> void:
	if sketch.texture == null:
		sketch.visible = false
		sketch.custom_minimum_size = Vector2.ZERO
		return
	sketch.visible = true
	# Short entries get more of the remaining page, while dense entries keep
	# a readable sketch without forcing the text itself out of view.
	var preferred_height := clampf(300.0 - float(page_text.length()) * 0.16, 112.0, 292.0)
	sketch.custom_minimum_size = Vector2(0, preferred_height)

func _journal_sketch_key(title: String, selected_species_id: String) -> String:
	var upper := title.to_upper()
	if "TANK READINGS" in upper:
		return "system_notes"
	if "RECENT TIMELINE" in upper:
		return "observations"
	if "FIELD NOTE" in upper:
		return "fish_" + selected_species_id
	if "AQUARIUM SYSTEM NOTES" in upper:
		return "system_notes"
	if "COMPATIBILITY" in upper:
		return "compatibility"
	if "REAL TIME" in upper:
		return "survival_time"
	if "MAINTENANCE CHEMISTRY" in upper:
		return "maintenance_chemistry"
	if "STABILITY MEMORY" in upper:
		return "stability_memory"
	if "WATER CHANGE" in upper:
		return "water_change"
	if "WOOD" in upper or "ROCK" in upper:
		return "hardscape"
	if "SUBSTRATE" in upper:
		return "substrate"
	if "PLANT MEMORY" in upper:
		return "plant_memory"
	if "PLANTS" in upper:
		return "plants"
	if "ALGAE" in upper:
		return "algae"
	if "CORAL POLYP MEMORY" in upper:
		return "coral_memory"
	if "CORAL" in upper or "REEF" in upper:
		return "coral"
	if "FEED" in upper:
		return "feeding"
	if "FISH ROUTINES" in upper:
		return "fish_routines"
	if "CLEANUP" in upper:
		return "cleanup_crews"
	if "EQUIPMENT" in upper:
		return "equipment"
	if "GAS" in upper or "LIGHT" in upper or "TEMPERATURE" in upper:
		return "temperature"
	if "REDOX" in upper:
		return "redox_organics"
	if "DISEASE" in upper:
		return "disease_stress"
	if "TANK MATURITY" in upper:
		return "tank_maturity"
	if "MAINTENANCE ACTIONS" in upper:
		return "maintenance_actions"
	if "CARE RESIDUE" in upper:
		return "care_residue"
	if "CURRENT OBSERVATIONS" in upper:
		return "observations"
	if "SOURCE" in upper:
		return "sources"
	return "cycle"

func _species_agenda_entry(species_id: String, spec: Dictionary, aquarium: Dictionary, water: Dictionary) -> String:
	var name := str(spec.get("common_name", species_id))
	var system := str(spec.get("water_type", "freshwater"))
	var ideal_temp: Array = spec.get("temperature_c", {}).get("ideal", [0.0, 0.0])
	var tolerated_temp: Array = spec.get("temperature_c", {}).get("tolerated", ideal_temp)
	var ideal_ph: Array = spec.get("ph", {}).get("ideal", [0.0, 0.0])
	var tolerated_ph: Array = spec.get("ph", {}).get("tolerated", ideal_ph)
	var ideal_gh: Array = spec.get("gh_dgh", {}).get("ideal", [0.0, 0.0])
	var min_litres := float(spec.get("minimum_litres", 0.0))
	var min_length := float(spec.get("minimum_tank_length_cm", 0.0))
	var current_litres := float(aquarium.get("effective_litres", 0.0))
	var current_length := float(aquarium.get("length_cm", 0.0))
	var same_system := str(water.get("system", "freshwater")) == system
	var physical_fit := current_litres >= min_litres and current_length >= min_length
	var current_fit := "reference only — active tank uses a different water system"
	if same_system:
		current_fit = "physical minimum met; compare chemistry and companions" if physical_fit else "active tank is below the minimum volume or swimming length"
	var lines: Array[String] = [
		"SPECIES PROFILE — %s" % name.to_upper(),
		str(spec.get("scientific_name", "Scientific name unavailable")),
		"",
		"%s · adult %.1f cm · about %.0f years · %s swimmer" % [system.capitalize(), float(spec.get("adult_cm", 0.0)), float(spec.get("lifespan_years", 0.0)), str(spec.get("swim_zone", "middle"))],
		"Home: at least %.0f L usable water and %.0f cm tank length. Group minimum %d; preferred %d." % [min_litres, min_length, int(spec.get("minimum_group", 1)), int(spec.get("preferred_group", spec.get("minimum_group", 1)))],
		"Social style: %s. Activity %.0f%%, territoriality %.0f%%, fin-nipping tendency %.0f%%." % [str(spec.get("social", "community")).replace("_", " "), float(spec.get("activity", 0.0)) * 100.0, float(spec.get("territoriality", 0.0)) * 100.0, float(spec.get("fin_nipping", 0.0)) * 100.0],
		"",
		"IDEAL WATER",
		"Temperature %.1f–%.1f C (tolerated %.1f–%.1f), pH %.1f–%.1f (tolerated %.1f–%.1f), GH %.0f–%.0f dGH." % [float(ideal_temp[0]), float(ideal_temp[1]), float(tolerated_temp[0]), float(tolerated_temp[1]), float(ideal_ph[0]), float(ideal_ph[1]), float(tolerated_ph[0]), float(tolerated_ph[1]), float(ideal_gh[0]), float(ideal_gh[1])],
		"Oxygen at least %.1f mg/L; nitrate warning near %.0f mg/L." % [float(spec.get("oxygen_min_mg_l", 5.0)), float(spec.get("nitrate_warning_mg_l", 20.0))],
	]
	if spec.has("salinity_ppt"):
		var salinity: Array = spec.get("salinity_ppt", {}).get("ideal", [34.0, 36.0])
		lines.append("Salinity %.1f–%.1f ppt." % [float(salinity[0]), float(salinity[1])])
	lines.append("")
	lines.append("DIET · %s" % ", ".join(spec.get("diet", [])).replace("_", " "))
	if spec.has("care_notes"):
		lines.append("Keeper note: %s" % str(spec.get("care_notes", "")))
	lines.append("Active-aquarium comparison: %s." % current_fit)
	if spec.has("sources"):
		lines.append("Research trail: %s" % _source_summary(spec.get("sources", [])))
	return "\n".join(lines)

func _compatibility_hint(species_id: String, spec: Dictionary) -> String:
	var system := str(spec.get("water_type", "freshwater"))
	var territoriality := float(spec.get("territoriality", 0.0))
	var mouth := float(spec.get("predator_mouth_cm", 0.0))
	var zone := str(spec.get("swim_zone", "middle"))
	var candidates: Array[String] = []
	for other_id in species.keys():
		if str(other_id) == species_id:
			continue
		var other: Dictionary = species[other_id]
		if str(other.get("water_type", "freshwater")) != system:
			continue
		if territoriality > 0.65 and str(other.get("swim_zone", "")) == zone:
			continue
		if mouth > 0.6 and float(other.get("adult_cm", 0.0)) < float(spec.get("adult_cm", 0.0)) * 0.7:
			continue
		if abs(float(other.get("nitrate_warning_mg_l", 20.0)) - float(spec.get("nitrate_warning_mg_l", 20.0))) > 20.0:
			continue
		candidates.append(str(other.get("common_name", other_id)))
		if candidates.size() >= 3:
			break
	if territoriality > 0.65:
		return "Compatibility clue: treat this one as a personality fish. Research quiet tankmates that stay out of its space; do not trust a simple community label."
	if int(spec.get("minimum_group", 1)) >= 6:
		return "Compatibility clue: solve the school first. After that, investigate peaceful species using other water layers, such as %s." % (", ".join(candidates) if not candidates.is_empty() else "other calm, same-water species")
	if candidates.is_empty():
		return "Compatibility clue: no obvious shortcut. Match water, adult size, temperament, and swimming layer before buying companions."
	return "Compatibility clue: possible research leads, not guarantees: %s." % ", ".join(candidates)

func _source_summary(sources: Array) -> String:
	var domains: Array[String] = []
	for source in sources.slice(0, 3):
		var text := str(source)
		text = text.replace("https://", "").replace("http://", "")
		domains.append(text.split("/")[0])
	return ", ".join(domains)

func _add_selected_animal(acclimated: bool) -> void:
	if species_select.item_count <= 0:
		if tool_label:
			tool_label.text = "No compatible fish are available for this water type."
		return
	if species_select.selected < 0:
		species_select.select(0)
	var id := str(species_select.get_item_metadata(species_select.selected))
	var spec: Dictionary = species.get(id, {})
	var minutes := int(spec.get("acclimation_minutes", 30)) if acclimated else 0
	selected_animal_tool = {"species_id": id, "acclimation_minutes": minutes}
	selected_scape_tool = {}
	selected_scape_object_id = ""
	if tool_label:
		if acclimated:
			tool_label.text = "Floating acclimation bag for %d minutes. Click open water to release with the net." % minutes
		else:
			tool_label.text = "Emergency net selected. Click open water to release, but skipping acclimation is dangerous."

func _select_animal(index: int) -> void:
	if index >= 0 and index < animal_ids.size():
		selected_animal_id = str(animal_ids[index])

func _animal_action_command(action: String, animal_id: String) -> Dictionary:
	var command := {"action": action, "animal_id": animal_id}
	for animal in state.get("animals", []):
		if str(animal.get("id", "")) == animal_id:
			command["species_id"] = str(animal.get("species_id", ""))
			break
	if animal_visuals.has(animal_id):
		var inner := _tank_inner()
		var pos: Vector2 = animal_visuals[animal_id].get("pos", inner.get_center())
		command["x"] = clamp((pos.x - inner.position.x) / inner.size.x, 0.0, 1.0)
		command["y"] = clamp((pos.y - inner.position.y) / inner.size.y, 0.0, 1.0)
	return command

func _remove_selected_animal() -> void:
	if selected_animal_id == "":
		return
	_write_command(_animal_action_command("remove_animal", selected_animal_id))
	selected_animal_id = ""

func _quarantine_selected_animal() -> void:
	if selected_animal_id == "":
		if tool_label:
			tool_label.text = "Select a resident first, then quarantine it for observation."
		return
	var command := _animal_action_command("quarantine_animal", selected_animal_id)
	command["days"] = 14.0
	_write_command(command)
	if tool_label:
		tool_label.text = "Selected animal moved to observation quarantine. Watch stress, appetite, and visible symptoms."

func _choose_scape_tool(category: String, item_type: String, label: String) -> void:
	selected_scape_tool = {"category": category, "type": item_type, "label": label}
	selected_scape_object_id = ""
	selected_animal_tool = {}
	if scape_selection_label:
		scape_selection_label.text = "Placing %s with the current object settings." % label
	if tool_label:
		tool_label.text = "Picked up %s. Its canvas preview shows scale, rotation, mirror, and depth before you place it." % label

func _scape_object_by_id(object_id: String) -> Dictionary:
	var scape = state.get("aquarium", {}).get("scape", {})
	if typeof(scape) != TYPE_DICTIONARY:
		return {}
	for obj in scape.get("objects", []):
		if str(obj.get("id", "")) == object_id:
			return obj
	return {}

func _scape_transform_values() -> Dictionary:
	var layer := 1
	if scape_layer_select and scape_layer_select.selected >= 0:
		layer = int(scape_layer_select.get_item_metadata(scape_layer_select.selected))
	return {
		"scale": float(scape_scale_spin.value) if scape_scale_spin else 1.0,
		"rotation": float(scape_rotation_spin.value) if scape_rotation_spin else 0.0,
		"layer": layer,
		"flipped": bool(scape_flip_check.button_pressed) if scape_flip_check else false,
	}

func _set_scape_transform_controls(obj: Dictionary) -> void:
	if scape_scale_spin:
		scape_scale_spin.value = float(obj.get("scale", 1.0))
	if scape_rotation_spin:
		scape_rotation_spin.value = float(obj.get("rotation", 0.0))
	if scape_flip_check:
		scape_flip_check.button_pressed = bool(obj.get("flipped", false))
	if scape_layer_select:
		var layer := int(obj.get("layer", 1))
		for index in range(scape_layer_select.item_count):
			if int(scape_layer_select.get_item_metadata(index)) == layer:
				scape_layer_select.select(index)
				break

func _select_scape_object(object_id: String) -> void:
	var obj := _scape_object_by_id(object_id)
	if obj.is_empty():
		return
	selected_scape_object_id = object_id
	selected_scape_tool = {}
	selected_animal_tool = {}
	_set_scape_transform_controls(obj)
	var title := str(obj.get("type", "scape item")).replace("_", " ").capitalize()
	var layer_index: int = clampi(int(obj.get("layer", 1)), 0, 2)
	var layer: String = ["back", "mid", "front"][layer_index]
	if scape_selection_label:
		scape_selection_label.text = "Selected %s, %.2fx, %s layer." % [title, float(obj.get("scale", 1.0)), layer]
	if tool_label:
		tool_label.text = "Selected %s. Click another valid point to relocate it, or adjust it in the object editor." % title

func _clear_scape_editor() -> void:
	selected_scape_tool = {}
	selected_scape_object_id = ""
	if scape_selection_label:
		scape_selection_label.text = "No piece selected. Placement settings are ready."
	if tool_label:
		tool_label.text = "Choose a piece, set its shape, then place it on the canvas."

func _apply_selected_scape_transform() -> void:
	if selected_scape_object_id == "":
		if tool_label:
			tool_label.text = "Select a placed object in the aquarium before applying a transform."
		return
	var command := _scape_object_action_command("move_scape_item", selected_scape_object_id)
	if command.size() <= 1:
		return
	var transform: Dictionary = _scape_transform_values()
	for key in transform:
		command[key] = transform[key]
	_write_command(command)
	if tool_label:
		tool_label.text = "Applied the selected piece's scale, rotation, mirror, and depth."

func _duplicate_selected_scape() -> void:
	if selected_scape_object_id == "":
		if tool_label:
			tool_label.text = "Select a placed object before duplicating it."
		return
	_write_command(_scape_object_action_command("duplicate_scape_item", selected_scape_object_id))
	if tool_label:
		tool_label.text = "Duplicated the selected piece beside the original so you can compose a cluster."

func _scape_object_action_command(action: String, object_id: String) -> Dictionary:
	var command := {"action": action, "object_id": object_id}
	var scape = state.get("aquarium", {}).get("scape", {})
	if typeof(scape) != TYPE_DICTIONARY:
		return command
	for obj in scape.get("objects", []):
		if str(obj.get("id", "")) != object_id:
			continue
		command["category"] = str(obj.get("category", ""))
		command["type"] = str(obj.get("type", ""))
		if obj.has("x"):
			command["x"] = float(obj.get("x", 0.5))
		if obj.has("y"):
			command["y"] = float(obj.get("y", 0.76))
		if obj.has("scale"):
			command["scale"] = float(obj.get("scale", 1.0))
		if obj.has("rotation"):
			command["rotation"] = float(obj.get("rotation", 0.0))
		if obj.has("layer"):
			command["layer"] = int(obj.get("layer", 1))
		if obj.has("flipped"):
			command["flipped"] = bool(obj.get("flipped", false))
		break
	return command

func _remove_selected_scape() -> void:
	if selected_scape_object_id == "":
		return
	_write_command(_scape_object_action_command("remove_scape_item", selected_scape_object_id))
	_clear_scape_editor()

func _nudge_selected_scape(delta: Vector2) -> void:
	if selected_scape_object_id == "":
		if tool_label:
			tool_label.text = "Select a piece before nudging it."
		return
	var command := _scape_object_action_command("move_scape_item", selected_scape_object_id)
	var next := Vector2(float(command.get("x", 0.5)), float(command.get("y", 0.76))) + delta
	if not _client_position_valid(str(command.get("category", "")), str(command.get("type", "")), next.clamp(Vector2.ZERO, Vector2.ONE), true):
		return
	command["x"] = clamp(next.x, 0.02, 0.98)
	command["y"] = clamp(next.y, 0.02, 0.98)
	_write_command(command)

func _rotate_selected_scape(delta: float) -> void:
	if selected_scape_object_id == "":
		if tool_label:
			tool_label.text = "Select a piece before rotating it."
		return
	var command := _scape_object_action_command("move_scape_item", selected_scape_object_id)
	command["rotation"] = fposmod(float(command.get("rotation", 0.0)) + delta + 180.0, 360.0) - 180.0
	_write_command(command)

func _write_command(command: Dictionary) -> void:
	var action := str(command.get("action", "command"))
	_add_action_effect(action, command)
	command["timestamp"] = Time.get_datetime_string_from_system()
	DirAccess.make_dir_recursive_absolute(root_dir.path_join("runtime"))
	DirAccess.make_dir_recursive_absolute(commands_dir)
	var path := commands_dir.path_join("%s-%d.json" % [action, Time.get_ticks_usec()])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(command, "\t"))
		last_command_note = "%s sent" % action.replace("_", " ")
		last_command_until = Time.get_ticks_msec() / 1000.0 + 1.8

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
		var start_pos: Vector2 = _release_point(animal, seed, spec.get("swim_zone", "middle"))
		var start_target: Vector2 = _seeded_point(seed + 31, spec.get("swim_zone", "middle"))
		var start_direction: Vector2 = (start_target - start_pos).normalized()
		if start_direction.length() < 0.01:
			start_direction = Vector2.RIGHT if seed % 2 == 0 else Vector2.LEFT
		var start_speed: float = lerp(16.0, 34.0, clamp(float(spec.get("activity", 0.5)), 0.0, 1.0))
		var visual := {
			"seed": seed,
			"species_id": animal.get("species_id", ""),
			"phase": float(seed % 628) / 100.0,
			"pos": start_pos,
			"target": start_target,
			"target_age": 0.0,
			"velocity": start_direction * start_speed,
			"facing": 1.0 if start_direction.x >= 0.0 else -1.0,
			"bank": 0.0,
			"turn_energy": 0.0,
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
	var school_contexts := _school_contexts(animals)
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
		var target_age: float = float(visual.get("target_age", 0.0)) + delta
		var routine := str(animal.get("routine", "explore"))
		var intent := str(animal.get("behavior_intent", ""))
		var behavior_profile: Dictionary = spec.get("behavior_profile", {})
		var movement_style := str(behavior_profile.get("movement", "general_roam"))
		var target_distance := pos.distance_to(target)
		# Hold a waypoint long enough to pass it smoothly. Refreshing as soon as a
		# fish touches a nearby target caused repeated left/right corrections.
		var can_refresh_target := routine not in ["hide", "hang_back"]
		var arrival_radius: float = 14.0 if routine == "rest" else 18.0
		var minimum_hold: float = 1.35 if routine == "rest" else 0.48
		var maximum_hold: float = 3.6 if routine == "rest" else 1.35
		if can_refresh_target and (target_distance < arrival_radius and target_age > minimum_hold or target_age > maximum_hold):
			var next_target := _routine_target(animal, spec, visual, school_contexts)
			# Non-school routines need a real next leg to travel. A generated point
			# that lands beside the fish is what made it rock back and forth in place.
			if routine != "school" and next_target.distance_to(pos) < 58.0:
				var travel_direction: Vector2 = visual.get("velocity", Vector2.ZERO) as Vector2
				if travel_direction.length() < 4.0:
					travel_direction = Vector2(1.0 if seed % 2 == 0 else -1.0, sin(seed * 0.73) * 0.34)
				next_target = _clamped_tank_point(pos + travel_direction.normalized() * 94.0)
			visual["target"] = next_target
			target = visual["target"]
			target_age = 0.0
		var feed_strength := _active_action_strength(["feed"])
		if feed_strength > 0.05 and not (routine in ["hide", "rest"]):
			target = _feeding_target_for_zone(zone, seed)
			visual["target"] = target
			target_age = 0.0
		var disturbance := _active_action_strength(DISTURBING_ACTIONS)
		if disturbance > 0.05:
			var source := _active_action_point(DISTURBING_ACTIONS, Vector2(0.52, 0.55))
			var away := pos - source
			if away.length() < 1.0:
				away = Vector2(1.0 if seed % 2 == 0 else -1.0, 0.35)
			target = _clamped_tank_point(source + away.normalized() * lerp(96.0, 230.0, disturbance) + Vector2(0, 32.0 * disturbance))
			visual["target"] = target
			target_age = 0.0
		var speed: float = lerp(18.0, 58.0, activity)
		speed *= lerp(0.62, 1.18, clamp(float(animal.get("activity_drive", 0.55)), 0.0, 1.0))
		speed *= lerp(0.78, 1.08, clamp(float(animal.get("confidence", 0.55)), 0.0, 1.0))
		speed *= lerp(1.04, 0.68, clamp(float(animal.get("fear_memory", 0.0)), 0.0, 1.0))
		if feed_strength > 0.05:
			speed *= lerp(1.0, 1.72, feed_strength)
		if disturbance > 0.05:
			speed *= lerp(1.0, 1.55, disturbance)
		if routine in ["rest", "hide", "hang_back"]:
			speed *= 0.42
		elif routine in ["flee", "pace"]:
			speed *= 1.45
		elif routine == "school":
			speed *= lerp(0.78, 1.02, clamp(float(animal.get("school_cohesion", 0.55)), 0.0, 1.0))
		if movement_style in ["fast_surface_laps", "long_school_laps", "reef_school_cruise"]:
			speed *= 1.16
		elif movement_style in ["hover_patrol", "hover_browse", "hover_group", "cleaner_station"]:
			speed *= 0.76
		elif movement_style in ["burrow_watch", "coral_perch", "perch_and_dash"]:
			speed *= 0.68
		elif movement_style in ["serpentine_bottom", "graze_and_shelter", "graze_crawl"]:
			speed *= 0.84
		if intent == "pausing nearby":
			speed *= 0.58
		elif intent == "inspecting current":
			speed *= 0.76
		elif intent == "scouting" or intent == "leading":
			speed *= 1.10
		elif intent == "current riding":
			speed *= 0.88
		elif intent == "conserving energy":
			speed *= 0.46
		var aim: Vector2 = target - pos
		var desired_velocity := Vector2.ZERO
		var settled: bool = routine in ["rest", "hide", "hang_back"] and aim.length() < 24.0
		if aim.length() > 1.0:
			# Ease into a waypoint instead of overshooting it and immediately turning
			# back. Resting fish stop steering once they have reached their shelter.
			var arrival_distance: float = 48.0 if routine == "rest" else 72.0
			var arrival_speed: float = clamp(aim.length() / arrival_distance, 0.0, 1.0)
			if routine in ["rest", "hide", "hang_back"] and aim.length() < 24.0:
				arrival_speed = 0.0
			desired_velocity = aim.normalized() * speed * arrival_speed
		if routine == "school":
			# Formation steering is deliberately weaker than shared forward travel;
			# otherwise separation can cancel the school direction and trap fish in
			# tiny left/right corrections around their formation slot.
			var school_context: Dictionary = school_contexts.get(str(animal.get("species_id", "")), {})
			var school_anchor: Vector2 = school_context.get("anchor", target) as Vector2
			var cruise: Vector2 = school_anchor - pos
			if cruise.length() > 10.0:
				desired_velocity += cruise.normalized() * speed * 0.46
			desired_velocity += _school_steering(animal, pos, animals, school_contexts) * speed * 0.30
		var current := _water_current_at(pos)
		if settled:
			# A resting fish has reached its shelter. Let it be still rather than
			# continuously drifting off its sleep point and correcting back again.
			current = Vector2.ZERO
		elif routine in ["rest", "hide", "hang_back"]:
			current *= 0.55
		# Current is visual texture, not propulsion. With the old unbounded filter
		# return, a slow or cautious fish could have its travel vector cancelled and
		# physically shimmy left/right forever instead of reaching its waypoint.
		var current_share: float = 0.46 if intent == "current riding" else 0.18 if routine in ["rest", "hide", "hang_back"] else 0.28
		current = current.limit_length(max(1.4, speed * current_share))
		var lateral := Vector2(-desired_velocity.y, desired_velocity.x).normalized()
		var glide: float = sin(Time.get_ticks_msec() / 1000.0 * (0.88 + activity * 0.36) + seed * 0.71)
		desired_velocity += current + lateral * glide * speed * lerp(0.028, 0.075, activity)
		var velocity: Vector2 = visual.get("velocity", desired_velocity) as Vector2
		if velocity.length() < 0.01:
			velocity = desired_velocity
		var response: float = lerp(2.6, 5.6, activity)
		if settled:
			response = 9.0
		if routine in ["flee", "pace"] or disturbance > 0.05:
			response *= 1.38
		velocity = velocity.lerp(desired_velocity, clamp(response * delta, 0.0, 1.0))
		var max_speed: float = max(10.0, speed * 1.28)
		if velocity.length() > max_speed:
			velocity = velocity.normalized() * max_speed
		var unbounded_next: Vector2 = pos + velocity * delta
		var next: Vector2 = _clamped_tank_point(unbounded_next)
		if next.distance_to(unbounded_next) > 0.5:
			velocity = Vector2(-velocity.x * 0.36, velocity.y * 0.72)
			visual["target"] = _routine_target(animal, spec, visual, school_contexts)
			target_age = 0.0
		var facing: float = float(visual.get("facing", 1.0))
		if abs(velocity.x) > 0.35:
			facing = 1.0 if velocity.x >= 0.0 else -1.0
		var heading: float = clamp(atan2(velocity.y, max(abs(velocity.x), 1.0)) * facing, -0.28, 0.28)
		var previous_bank: float = float(visual.get("bank", 0.0))
		visual["facing"] = facing
		visual["pos"] = next
		visual["velocity"] = velocity
		visual["target_age"] = target_age
		visual["bank"] = lerp(previous_bank, heading, clamp(delta * 7.0, 0.0, 1.0))
		visual["turn_energy"] = clamp(abs(heading - previous_bank) * 6.5, 0.0, 1.0)
		visual["phase"] = float(visual["phase"]) + delta * (1.5 + activity * 1.8 + velocity.length() * 0.022)
		visual["speed_ratio"] = clamp(velocity.length() / 82.0, 0.0, 1.8)
		animal_visuals[id] = visual

func _school_contexts(animals: Array) -> Dictionary:
	var accum := {}
	var counts := {}
	var zones := {}
	for animal in animals:
		if not bool(animal.get("alive", true)):
			continue
		var spec = species.get(animal.get("species_id", ""), {})
		if not _is_schooling_social(str(spec.get("social", ""))):
			continue
		var id := str(animal.get("id", ""))
		if not animal_visuals.has(id):
			continue
		var species_id := str(animal.get("species_id", ""))
		accum[species_id] = accum.get(species_id, Vector2.ZERO) + animal_visuals[id].get("pos", Vector2.ZERO)
		counts[species_id] = int(counts.get(species_id, 0)) + 1
		zones[species_id] = str(spec.get("swim_zone", "middle"))
	var contexts := {}
	for key in accum.keys():
		var species_id := str(key)
		var center: Vector2 = accum[key] / max(1, int(counts.get(key, 1)))
		var anchor := _school_anchor(species_id, str(zones.get(species_id, "middle")))
		contexts[species_id] = {"center": center, "anchor": anchor, "count": int(counts.get(key, 1))}
	return contexts

func _school_anchor(species_id: String, zone: String) -> Vector2:
	var species_seed: int = abs(species_id.hash()) % 100000
	return _moving_target(species_seed, zone)

func _is_schooling_social(social: String) -> bool:
	return social.contains("school") or social.contains("shoal") or social == "loose_group"

func _school_steering(animal: Dictionary, pos: Vector2, animals: Array, contexts: Dictionary) -> Vector2:
	var species_id := str(animal.get("species_id", ""))
	var cohesion: float = clamp(float(animal.get("school_cohesion", 0.55)), 0.0, 1.0)
	var spacing: float = lerp(52.0, 30.0, cohesion) * clamp(float(animal.get("school_spacing", 1.0)), 0.72, 1.30)
	var steering := Vector2.ZERO
	for other in animals:
		var other_id := str(other.get("id", ""))
		if other_id == str(animal.get("id", "")) or not animal_visuals.has(other_id):
			continue
		var other_spec: Dictionary = species.get(str(other.get("species_id", "")), {})
		if not _is_schooling_social(str(other_spec.get("social", ""))):
			continue
		var other_pos: Vector2 = animal_visuals[other_id].get("pos", Vector2.ZERO)
		var delta: Vector2 = pos - other_pos
		var distance: float = max(1.0, delta.length())
		if str(other.get("species_id", "")) == species_id:
			if distance < spacing:
				steering += delta.normalized() * (1.0 - distance / spacing) * 0.78
		elif distance < 108.0:
			steering += delta.normalized() * (1.0 - distance / 108.0) * 0.52
	var context: Dictionary = contexts.get(species_id, {})
	var anchor: Vector2 = context.get("anchor", pos) as Vector2
	steering += (anchor - pos).normalized() * 0.22
	return steering.limit_length(1.0)

func _routine_target(animal: Dictionary, spec: Dictionary, visual: Dictionary, school_contexts: Dictionary) -> Vector2:
	var inner := _tank_inner()
	var seed: int = int(visual.get("seed", 1))
	var zone := str(spec.get("swim_zone", "middle"))
	var routine := str(animal.get("routine", "explore"))
	var home := inner.position + Vector2(float(animal.get("home_x", 0.5)) * inner.size.x, float(animal.get("home_y", 0.5)) * inner.size.y)
	var sleep := inner.position + Vector2(float(animal.get("sleep_x", animal.get("home_x", 0.5))) * inner.size.x, float(animal.get("sleep_y", animal.get("home_y", 0.5))) * inner.size.y)
	match routine:
		"rest":
			# Sleep is a small, intentional circuit around a familiar refuge—not a
			# frozen pose, and not jitter driven by the current.
			var rest_step: int = int(floor(Time.get_ticks_msec() / 3600.0) + seed) % 6
			var rest_angle: float = float(rest_step) * TAU / 6.0
			var rest_base := _species_habitat_target(animal, spec, seed, rest_step, sleep, true)
			var rest_radius: float = 12.0 if str(spec.get("behavior_profile", {}).get("movement", "")) in ["coral_perch", "burrow_watch", "perch_and_dash"] else 24.0
			var rest_offset := Vector2(cos(rest_angle) * rest_radius, sin(rest_angle) * rest_radius * 0.48)
			return Vector2(clamp(rest_base.x + rest_offset.x, inner.position.x + 34, inner.end.x - 34), clamp(rest_base.y + rest_offset.y, inner.position.y + 48, inner.end.y - 42))
		"hide":
			return Vector2(clamp(home.x, inner.position.x + 34, inner.end.x - 34), clamp(max(home.y, inner.end.y - _substrate_height() - 120), inner.position.y + 48, inner.end.y - 42))
		"surface":
			return Vector2(inner.position.x + 60.0 + fposmod(seed * 37.0 + Time.get_ticks_msec() / 20.0, inner.size.x - 120.0), inner.position.y + 46.0)
		"forage":
			return Vector2(inner.position.x + 50.0 + fposmod(seed * 71.0 + Time.get_ticks_msec() / 24.0, inner.size.x - 100.0), inner.end.y - _substrate_height() - 22.0 - fposmod(seed * 11.0, 34.0))
		"graze":
			return Vector2(inner.position.x + 54.0 + fposmod(seed * 47.0 + Time.get_ticks_msec() / 36.0, inner.size.x - 108.0), inner.end.y - _substrate_height() - 42.0 - fposmod(seed * 13.0, 56.0))
		"sift":
			return Vector2(inner.position.x + 48.0 + fposmod(seed * 59.0 + Time.get_ticks_msec() / 28.0, inner.size.x - 96.0), inner.end.y - _substrate_height() - 18.0 - fposmod(seed * 7.0, 20.0))
		"surface_patrol":
			return Vector2(inner.position.x + 56.0 + fposmod(seed * 53.0 + Time.get_ticks_msec() / 22.0, inner.size.x - 112.0), inner.position.y + 58.0 + fposmod(seed * 5.0, 34.0))
		"current":
			return _moving_target(seed + int(Time.get_ticks_msec() / 1300), zone)
		"territory":
			return Vector2(clamp(home.x + sin(Time.get_ticks_msec() / 700.0 + seed) * 72.0, inner.position.x + 44, inner.end.x - 44), clamp(home.y + cos(Time.get_ticks_msec() / 830.0 + seed) * 38.0, inner.position.y + 54, inner.end.y - _substrate_height() - 38))
		"perch":
			return _species_habitat_target(animal, spec, seed, int(Time.get_ticks_msec() / 4200), home, false)
		"cave_watch":
			return _species_habitat_target(animal, spec, seed, int(Time.get_ticks_msec() / 3600), home, false)
		"host":
			var host := _species_habitat_target(animal, spec, seed, 0, home, false)
			return host + Vector2(cos(Time.get_ticks_msec() / 900.0 + seed) * 34.0, sin(Time.get_ticks_msec() / 1100.0 + seed) * 22.0)
		"burrow":
			return _species_habitat_target(animal, spec, seed, 0, home, false)
		"hover":
			return home + Vector2(sin(Time.get_ticks_msec() / 1500.0 + seed) * 42.0, cos(Time.get_ticks_msec() / 1850.0 + seed) * 24.0)
		"dart":
			return _moving_target(seed + int(Time.get_ticks_msec() / 620), zone)
		"school":
			var species_id := str(animal.get("species_id", ""))
			var context: Dictionary = school_contexts.get(species_id, {})
			var center: Vector2 = context.get("center", _moving_target(seed, zone)) as Vector2
			var anchor: Vector2 = context.get("anchor", _school_anchor(species_id, zone)) as Vector2
			var cohesion: float = clamp(float(animal.get("school_cohesion", 0.55)), 0.0, 1.0)
			var school_center := center.lerp(anchor, 0.58)
			var spread: float = lerp(76.0, 26.0, cohesion) * clamp(float(animal.get("school_spacing", 1.0)), 0.72, 1.30)
			var heading := (anchor - center).normalized()
			if heading.length() < 0.05:
				heading = Vector2.RIGHT
			var side := Vector2(-heading.y, heading.x)
			var phase := float(seed % 97) * 0.41 + Time.get_ticks_msec() / 1700.0
			var offset: Vector2 = side * sin(phase) * spread + heading * cos(phase * 1.37) * spread * 0.32
			var intent := str(animal.get("behavior_intent", "following"))
			if intent == "scouting":
				offset += side * sign(sin(phase * 1.8)) * spread * 1.15 + heading * spread * 0.56
			elif intent == "regrouping":
				offset *= 0.28
			elif intent == "leading":
				offset += heading * spread * 0.54
			elif intent == "feeding lane":
				offset += heading * spread * 0.34 + Vector2(0, spread * 0.22)
			elif intent == "current riding":
				offset += heading * spread * 0.20
			return Vector2(clamp(school_center.x + offset.x, inner.position.x + 52, inner.end.x - 52), clamp(school_center.y + offset.y, inner.position.y + 54, inner.end.y - _substrate_height() - 38))
		"flee":
			return Vector2(inner.position.x + 42.0 + fposmod(seed * 91.0, inner.size.x - 84.0), inner.position.y + inner.size.y * 0.72)
		"display", "patrol":
			return _moving_target(seed + int(Time.get_ticks_msec() / 900), zone)
		"inspect":
			var curiosity := float(animal.get("curiosity", 0.5))
			return Vector2(inner.position.x + 52.0 + fposmod(seed * 43.0 + Time.get_ticks_msec() / lerp(34.0, 15.0, curiosity), inner.size.x - 104.0), _zone_y(zone, fposmod(sin(Time.get_ticks_msec() / 1100.0 + seed) * 0.5 + 0.5, 1.0)))
	return _moving_target(seed, zone)

func _species_habitat_target(animal: Dictionary, spec: Dictionary, seed: int, step: int, fallback: Vector2, resting: bool) -> Vector2:
	var profile: Dictionary = spec.get("behavior_profile", {})
	var sites: Array = profile.get("rest_sites", [])
	var inner := _tank_inner()
	var candidates: Array[Vector2] = []
	var scape: Dictionary = state.get("aquarium", {}).get("scape", {})
	var objects: Array = scape.get("objects", []) if typeof(scape) == TYPE_DICTIONARY else []
	for value in objects:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var obj: Dictionary = value
		var category := str(obj.get("category", ""))
		var item_type := str(obj.get("type", ""))
		var matched_site := _matching_rest_site(sites, category, item_type)
		if matched_site == "":
			continue
		var point: Vector2 = _object_pos(obj, fallback)
		var draw_size: Vector2 = _scape_object_draw_size(category, item_type) * clamp(float(obj.get("scale", 1.0)), 0.35, 2.4)
		if matched_site in ["broad_leaf", "wood_top", "rock_top", "coral_host"]:
			point.y -= draw_size.y * (0.34 if matched_site == "broad_leaf" else 0.46)
		elif matched_site in ["cave", "rock_crevice", "rock_overhang", "burrow"]:
			point += Vector2(draw_size.x * 0.18, draw_size.y * 0.12)
		candidates.append(_clamped_tank_point(point))
	# Legacy quantity-based scapes have no object coordinates, but still provide
	# real resting habitat in the rendered tank.
	for site_value in sites:
		var site := str(site_value)
		if site in ["wood_top", "wood_shadow", "cave"] and not _scape_items("wood").is_empty():
			candidates.append(Vector2(inner.position.x + inner.size.x * 0.48, inner.end.y - _substrate_height() - (92.0 if site == "wood_top" else 48.0)))
		elif site in ["rock_top", "rock_crevice", "rock_overhang", "burrow"] and not _scape_items("rocks").is_empty():
			candidates.append(Vector2(inner.position.x + inner.size.x * 0.43, inner.end.y - _substrate_height() - (64.0 if site == "rock_top" else 28.0)))
		elif site == "coral_host" and not _scape_items("corals").is_empty():
			candidates.append(Vector2(inner.position.x + inner.size.x * 0.52, inner.end.y - _substrate_height() - 76.0))
		elif site in ["broad_leaf", "plant_thicket"] and not _scape_items("plants").is_empty():
			candidates.append(Vector2(inner.position.x + inner.size.x * (0.22 if seed % 2 == 0 else 0.78), inner.end.y - _substrate_height() - (108.0 if site == "broad_leaf" else 72.0)))
		elif site == "surface_cover":
			candidates.append(Vector2(inner.position.x + inner.size.x * (0.24 + float(seed % 5) * 0.13), inner.position.y + 62.0))
		elif site == "substrate":
			candidates.append(Vector2(fallback.x, inner.end.y - _substrate_height() - 18.0))
		elif site == "open_water" and not resting:
			candidates.append(_moving_target(seed, str(profile.get("rest_zone", spec.get("swim_zone", "middle")))))
	if candidates.is_empty():
		return fallback
	return candidates[posmod(seed + step, candidates.size())]

func _matching_rest_site(sites: Array, category: String, item_type: String) -> String:
	for value in sites:
		var site := str(value)
		if site == "broad_leaf" and category == "plants" and item_type in ["anubias", "amazon_sword", "java_fern", "cryptocoryne_wendtii"]:
			return site
		if site in ["wood_top", "wood_shadow"] and category == "wood":
			return site
		if site in ["rock_top", "rock_crevice", "rock_overhang", "cave", "burrow"] and category == "rocks":
			return site
		if site == "coral_host" and category == "corals":
			return site
		if site == "plant_thicket" and category == "plants":
			return site
	return ""

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

func _release_point(animal: Dictionary, seed: int, zone: String) -> Vector2:
	if animal.has("release_x") and animal.has("release_y"):
		var inner := _tank_inner()
		return inner.position + Vector2(float(animal["release_x"]) * inner.size.x, float(animal["release_y"]) * inner.size.y)
	return _seeded_point(seed, zone)

func _moving_target(seed: int, zone: String) -> Vector2:
	var t := Time.get_ticks_msec() / 1000.0
	var inner := _tank_inner()
	var x := inner.position.x + 52.0 + fposmod(sin(t * 0.7 + seed) * 0.5 + 0.5 + float(seed % 13) * 0.073, 1.0) * (inner.size.x - 104.0)
	var y := _zone_y(zone, fposmod(cos(t * 0.53 + seed * 0.31) * 0.5 + 0.5, 1.0))
	return Vector2(x, y)

func _clamped_tank_point(point: Vector2) -> Vector2:
	var inner := _tank_inner()
	return Vector2(
		clamp(point.x, inner.position.x + 42.0, inner.end.x - 42.0),
		clamp(point.y, inner.position.y + 44.0, inner.end.y - _substrate_height() - 18.0)
	)

func _water_current_at(point: Vector2) -> Vector2:
	var equipment: Dictionary = state.get("equipment", {})
	var filter: Dictionary = equipment.get("filter", {})
	var air: Dictionary = equipment.get("air_pump", {})
	var flow: float = clamp(float(filter.get("effective_flow", filter.get("flow", 0.0))) if bool(filter.get("enabled", true)) else 0.0, 0.0, 1.0)
	var air_output: float = clamp(float(air.get("effective_output", air.get("output", 0.0))) if bool(air.get("enabled", true)) else 0.0, 0.0, 1.0)
	var inner := _tank_inner()
	var depth: float = clamp((point.y - inner.position.y) / max(1.0, inner.size.y), 0.0, 1.0)
	var t: float = Time.get_ticks_msec() / 1000.0
	var return_flow: float = lerp(2.2, 15.0, flow) * lerp(0.70, 1.10, depth)
	var vertical: float = sin(t * 1.4 + point.x * 0.021) * (0.8 + flow * 2.8)
	var air_stone := Vector2(inner.position.x + inner.size.x * 0.18, inner.end.y - _substrate_height() - 18.0)
	var air_distance: float = point.distance_to(air_stone)
	var air_lift: float = clamp(1.0 - air_distance / max(90.0, inner.size.x * 0.34), 0.0, 1.0) * air_output * 7.5
	return Vector2(-return_flow, vertical - air_lift)

func _feeding_target_for_zone(zone: String, seed: int) -> Vector2:
	var inner := _tank_inner()
	var effect := _latest_action_effect(["feed"])
	var food_type := str(effect.get("food_type", "community_flake"))
	var base_x := inner.position.x + inner.size.x * (0.36 + sin(seed * 0.77) * 0.10)
	var y_ratio := 0.32
	match food_type:
		"sinking_wafer", "algae_wafer":
			y_ratio = 0.78
		"micro_pellet":
			y_ratio = 0.48
		"frozen_invertebrates":
			y_ratio = 0.44
		"reef_plankton":
			y_ratio = 0.36
		_:
			y_ratio = 0.22 if zone == "upper" else 0.34
	if zone == "bottom":
		y_ratio = max(y_ratio, 0.74)
	return _clamped_tank_point(Vector2(base_x + sin(seed * 1.9) * 42.0, inner.position.y + inner.size.y * y_ratio + cos(seed) * 18.0))

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
	var light_factor := _clock_light_factor()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#05090c").lerp(Color("#071013"), light_factor))
	var aquarium := _aquarium_rect()
	draw_rect(Rect2(0, 0, size.x, TOP_BAR + 22.0), Color("#070c10").lerp(Color("#0b1418"), light_factor))
	draw_rect(Rect2(aquarium.position + Vector2(-6, -6), aquarium.size + Vector2(12, 12)), Color("#0a1114").lerp(Color("#0f1d21"), light_factor))
	draw_rect(Rect2(EDGE, 26, 15, 20), Color("#ff776a"))
	draw_rect(Rect2(EDGE + 20, 18, 15, 28), Color("#5bc5dc"))
	draw_rect(Rect2(EDGE + 40, 12, 15, 34), Color("#f2cf68"))

func _clock_light_factor() -> float:
	var clock = state.get("clock", {})
	var phase := str(clock.get("day_phase", "day"))
	if bool(clock.get("lights_on", true)):
		return 1.0
	match phase:
		"dawn":
			return 0.42
		"dusk":
			return 0.36
		_:
			return 0.16

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
	var symptoms = state.get("symptoms", {})
	var turbidity: float = clamp(float(water.get("turbidity", 0.0)), 0.0, 1.0)
	var ammonia: float = clamp(float(water.get("ammonia_mg_l", 0.0)) * 2.0, 0.0, 1.0)
	var nitrate: float = clamp(max(0.0, float(water.get("nitrate_mg_l", 0.0)) - 20.0) / 40.0, 0.0, 1.0)
	var green_water: float = clamp(float(symptoms.get("green_water", 0.0)), 0.0, 1.0)
	var maintenance_haze: float = clamp(float(symptoms.get("maintenance_haze", 0.0)), 0.0, 1.0)
	var film: float = clamp(float(symptoms.get("surface_film", water.get("surface_film", 0.0))), 0.0, 1.0)
	if turbidity > 0.02:
		draw_rect(inner, Color(0.46, 0.36, 0.18, turbidity * 0.18), true)
	if maintenance_haze > 0.02:
		draw_rect(inner, Color(0.72, 0.68, 0.54, maintenance_haze * 0.10), true)
		for m in range(int(10 + maintenance_haze * 55.0)):
			var speck := Vector2(
				inner.position.x + 18.0 + fposmod(m * 83.0 + Time.get_ticks_msec() / 80.0, inner.size.x - 36.0),
				inner.position.y + 42.0 + fposmod(m * 37.0 + sin(Time.get_ticks_msec() / 700.0 + m) * 18.0, inner.size.y - 96.0)
			)
			draw_circle(speck, 1.2 + float(m % 3) * 0.5, Color(0.85, 0.78, 0.58, 0.07 + maintenance_haze * 0.09))
	if green_water > 0.02:
		draw_rect(inner, Color(0.18, 0.48, 0.18, green_water * 0.16), true)
	if ammonia > 0.02:
		draw_rect(inner, Color(0.78, 0.70, 0.30, ammonia * 0.16), true)
	if nitrate > 0.02:
		draw_rect(inner, Color(0.22, 0.56, 0.22, nitrate * 0.14), true)
	if film > 0.03:
		draw_rect(Rect2(inner.position + Vector2(24, 20), Vector2(inner.size.x - 48, 7 + film * 9.0)), Color(0.92, 0.96, 0.82, 0.08 + film * 0.18), true)
	_draw_day_night_water_overlay(inner)
	var water_level: float = clamp(float(water.get("water_level", 1.0)), 0.55, 1.0)
	if water_level < 0.995:
		var gap_h := (1.0 - water_level) * inner.size.y * 0.72
		draw_rect(Rect2(inner.position, Vector2(inner.size.x, gap_h)), Color("#071013", 0.72), true)
		draw_line(inner.position + Vector2(18, gap_h), inner.position + Vector2(inner.size.x - 18, gap_h), Color(0.84, 0.96, 1.0, 0.34), 2.0, true)
	_draw_water_light_volume(inner, water_level)
	_draw_water_seasoning(inner)
	_draw_specific_algae(inner)
	_draw_current_flow_lines(inner)
	for i in range(3):
		var y := inner.position.y + 24.0 + i * 18.0 + sin(Time.get_ticks_msec() / 900.0 + i) * 3.0
		_draw_wave(Vector2(inner.position.x + 18.0, y), inner.size.x - 36.0, Color(0.74, 0.94, 0.98, 0.16), 2.0 + i)
	_draw_substrate(inner)
	draw_rect(tank, Color("#416973"), false, 3.0)
	draw_rect(inner, Color(1, 1, 1, 0.045), false, 1.0)

func _draw_day_night_water_overlay(inner: Rect2) -> void:
	var clock = state.get("clock", {})
	var phase := str(clock.get("day_phase", "day"))
	var lights_on := bool(clock.get("lights_on", true))
	if lights_on:
		draw_rect(Rect2(inner.position.x + 32, inner.position.y + 8, inner.size.x - 64, inner.size.y * 0.32), Color(0.90, 0.98, 1.0, 0.045), true)
		return
	if phase == "dawn":
		draw_rect(inner, Color(0.86, 0.62, 0.36, 0.12), true)
	elif phase == "dusk":
		draw_rect(inner, Color(0.35, 0.22, 0.48, 0.16), true)
	else:
		draw_rect(inner, Color(0.01, 0.02, 0.07, 0.42), true)
		for i in range(4):
			var y := inner.position.y + 44.0 + i * 42.0 + sin(Time.get_ticks_msec() / 1400.0 + i) * 2.0
			_draw_wave(Vector2(inner.position.x + 34.0, y), inner.size.x - 68.0, Color(0.48, 0.68, 0.92, 0.055), 1.4 + i * 0.4)

func _draw_water_light_volume(inner: Rect2, water_level: float) -> void:
	var clock: Dictionary = state.get("clock", {})
	if not bool(clock.get("lights_on", true)):
		return
	var equipment: Dictionary = state.get("equipment", {})
	var light: Dictionary = equipment.get("light", {})
	var par: float = clamp(float(light.get("par_output", light.get("health", 1.0))), 0.0, 1.0)
	var spectrum: float = clamp(float(light.get("effective_spectrum", light.get("plant_spectrum", 0.82))), 0.0, 1.0)
	var water: Dictionary = state.get("water", {})
	var system := str(water.get("system", "freshwater"))
	var water_top: float = inner.position.y + (1.0 - water_level) * inner.size.y * 0.72
	var water_bottom: float = inner.end.y - _substrate_height() - 8.0
	if water_bottom <= water_top + 30.0:
		return
	var intensity: float = lerp(0.42, 1.0, par * spectrum)
	var light_color := Color(0.76, 0.98, 0.86, 1.0) if system == "freshwater" else Color(0.70, 0.91, 1.0, 1.0)
	var t: float = Time.get_ticks_msec() / 1000.0
	draw_rect(Rect2(inner.position.x + 18.0, water_top + 2.0, inner.size.x - 36.0, 18.0), Color(light_color.r, light_color.g, light_color.b, 0.025 * intensity), true)
	for shaft in range(5):
		var top_x: float = inner.position.x + inner.size.x * (0.10 + float(shaft) * 0.20) + sin(t * 0.42 + shaft * 1.7) * 20.0
		var bottom_x: float = top_x + sin(t * 0.58 + shaft * 2.1) * 64.0 - 22.0
		var top_width: float = 42.0 + float(shaft % 2) * 18.0
		var bottom_width: float = 128.0 + float((shaft + 1) % 3) * 22.0
		var points := PackedVector2Array([
			Vector2(top_x - top_width * 0.5, water_top + 4.0),
			Vector2(top_x + top_width * 0.5, water_top + 4.0),
			Vector2(bottom_x + bottom_width * 0.5, water_bottom),
			Vector2(bottom_x - bottom_width * 0.5, water_bottom),
		])
		var shaft_alpha: float = (0.012 + float(shaft % 2) * 0.006) * intensity
		draw_polygon(points, PackedColorArray([
			Color(light_color.r, light_color.g, light_color.b, shaft_alpha * 1.5),
			Color(light_color.r, light_color.g, light_color.b, shaft_alpha * 1.5),
			Color(light_color.r, light_color.g, light_color.b, shaft_alpha * 0.10),
			Color(light_color.r, light_color.g, light_color.b, shaft_alpha * 0.10),
		]))
	for ripple in range(5):
		var surface_y: float = water_top + 6.0 + float(ripple) * 2.4
		var surface_points := PackedVector2Array()
		for point in range(38):
			var x: float = inner.position.x + 14.0 + float(point) * (inner.size.x - 28.0) / 37.0
			var y: float = surface_y + sin(t * 2.6 + point * 0.61 + ripple) * (0.9 + ripple * 0.18)
			surface_points.push_back(Vector2(x, y))
		draw_polyline(surface_points, Color(light_color.r, light_color.g, light_color.b, (0.045 - ripple * 0.005) * intensity), 1.0, true)
	for caustic in range(24):
		var column: float = fposmod(float(caustic) * 0.173 + t * (0.025 + float(caustic % 3) * 0.006), 1.0)
		var row: float = fposmod(float(caustic) * 0.317 + sin(t * 0.44 + caustic) * 0.06, 1.0)
		var pos := Vector2(
			inner.position.x + 36.0 + column * (inner.size.x - 72.0),
			lerp(water_top + 34.0, water_bottom - 26.0, row)
		)
		var radius_x: float = 9.0 + float(caustic % 5) * 2.6
		var radius_y: float = 2.6 + float(caustic % 3) * 0.9
		var alpha: float = (0.018 + float(caustic % 4) * 0.005) * intensity * lerp(1.0, 0.36, row)
		_draw_ellipse(pos, radius_x, radius_y, Color(light_color.r, light_color.g, light_color.b, alpha), false, 1.0)
		if caustic % 2 == 0:
			draw_line(pos + Vector2(-radius_x * 0.62, 0), pos + Vector2(radius_x * 0.56, sin(t * 2.0 + caustic) * 2.2), Color(light_color.r, light_color.g, light_color.b, alpha * 0.66), 0.9, true)
	for mote in range(18):
		var mote_column: float = fposmod(float(mote) * 0.193 + t * 0.011, 1.0)
		var mote_row: float = fposmod(float(mote) * 0.271 - t * (0.012 + float(mote % 3) * 0.002), 1.0)
		var mote_pos := Vector2(inner.position.x + 28.0 + mote_column * (inner.size.x - 56.0), lerp(water_top + 30.0, water_bottom - 18.0, mote_row))
		draw_circle(mote_pos, 0.7 + float(mote % 3) * 0.28, Color(light_color.r, light_color.g, light_color.b, (0.035 + float(mote % 3) * 0.008) * intensity))

func _draw_current_flow_lines(inner: Rect2) -> void:
	var equipment: Dictionary = state.get("equipment", {})
	var filter: Dictionary = equipment.get("filter", {})
	var air: Dictionary = equipment.get("air_pump", {})
	var flow: float = clamp(float(filter.get("effective_flow", filter.get("flow", 0.0))), 0.0, 1.0)
	var air_output: float = clamp(float(air.get("effective_output", air.get("output", 0.0))) if bool(air.get("enabled", true)) else 0.0, 0.0, 1.0)
	var t: float = Time.get_ticks_msec() / 1000.0
	var count: int = int(7 + flow * 12.0 + air_output * 5.0)
	for i in range(count):
		var lane: float = float(i) / max(1.0, float(count - 1))
		var y: float = lerp(inner.position.y + 72.0, inner.end.y - _substrate_height() - 42.0, lane)
		var travel: float = fposmod(t * (0.05 + flow * 0.12) + float(i) * 0.137, 1.0)
		var x: float = lerp(inner.end.x - 82.0, inner.position.x + 62.0, travel)
		var points := PackedVector2Array()
		for p in range(7):
			var offset: float = float(p) * 10.0
			points.push_back(Vector2(x + offset, y + sin(t * 1.7 + i + p * 0.9) * (2.0 + flow * 4.0)))
		draw_polyline(points, Color(0.78, 0.96, 1.0, 0.022 + flow * 0.050), 1.2, true)
	if air_output > 0.05:
		var stone := Vector2(inner.position.x + inner.size.x * 0.18, inner.end.y - _substrate_height() - 16)
		for r in range(3):
			var p: float = fposmod(t * (0.18 + r * 0.04), 1.0)
			draw_arc(stone + Vector2(0, -p * inner.size.y * 0.46), 22.0 + p * 58.0 + r * 11.0, -PI * 0.20, PI * 1.20, 34, Color(0.74, 0.94, 1.0, air_output * 0.045 * (1.0 - p)), 1.2, true)

func _draw_specific_algae(inner: Rect2) -> void:
	var symptoms = state.get("symptoms", {})
	var hair := float(symptoms.get("hair_algae", 0.0))
	var cyano := float(symptoms.get("cyanobacteria", 0.0))
	var bba := float(symptoms.get("black_beard_algae", 0.0))
	var sand_top := inner.end.y - _substrate_height()
	if hair > 0.05:
		for i in range(int(8 + hair * 42.0)):
			var root := Vector2(inner.position.x + 24.0 + fposmod(i * 67.0, inner.size.x - 48.0), sand_top - 6.0 - fposmod(i * 17.0, 54.0))
			var height := 10.0 + float(i % 5) * 5.0 + hair * 22.0
			var sway := sin(Time.get_ticks_msec() / 850.0 + i) * (2.0 + hair * 4.0)
			draw_line(root, root + Vector2(sway, -height), Color(0.34, 0.62, 0.28, 0.08 + hair * 0.18), 1.4, true)
	if cyano > 0.04:
		for i in range(int(4 + cyano * 18.0)):
			var mat_pos := Vector2(inner.position.x + 28.0 + fposmod(i * 113.0, inner.size.x - 72.0), sand_top - 10.0 - float(i % 4) * 7.0)
			var mat_size := Vector2(34.0 + cyano * 42.0, 7.0 + cyano * 10.0)
			draw_rect(Rect2(mat_pos, mat_size), Color(0.08, 0.40, 0.36, 0.06 + cyano * 0.18), true)
			draw_line(mat_pos + Vector2(4.0, mat_size.y * 0.55), mat_pos + Vector2(mat_size.x - 4.0, mat_size.y * 0.48), Color(0.18, 0.72, 0.62, 0.08 + cyano * 0.18), 1.4, true)
	if bba > 0.04:
		for i in range(int(5 + bba * 24.0)):
			var base := Vector2(inner.position.x + 38.0 + fposmod(i * 91.0, inner.size.x - 76.0), sand_top - 28.0 - fposmod(i * 23.0, inner.size.y * 0.42))
			for strand in range(4):
				var angle := -PI * 0.62 + float(strand) * 0.42 + sin(i + strand) * 0.18
				draw_line(base, base + Vector2(cos(angle), sin(angle)) * (8.0 + bba * 14.0), Color(0.05, 0.08, 0.07, 0.16 + bba * 0.26), 1.3, true)

func _substrate_height() -> float:
	var aquarium = state.get("aquarium", {})
	var depth: float = clamp(float(aquarium.get("substrate_depth_cm", 5.0)), 0.0, 9.0)
	return lerp(6.0, 112.0, depth / 9.0)

func _draw_substrate(inner: Rect2) -> void:
	var aquarium = state.get("aquarium", {})
	var kind := str(aquarium.get("substrate", "fine_sand"))
	var height := 0.0 if kind == "bare_bottom" else _substrate_height()
	if height <= 1.0:
		draw_rect(Rect2(inner.position.x, inner.end.y - 8.0, inner.size.x, 8.0), Color(0.12, 0.20, 0.21, 0.5), true)
		draw_line(Vector2(inner.position.x, inner.end.y - 8.0), Vector2(inner.end.x, inner.end.y - 8.0), Color(0.65, 0.9, 0.95, 0.18), 1.0, true)
		return
	var bed := Rect2(inner.position.x, inner.end.y - height, inner.size.x, height)
	var base := Color("#786d54")
	var speck := Color(0.90, 0.79, 0.56, 0.34)
	var particle_count := 90
	var max_radius := 1.8
	match kind:
		"rounded_gravel":
			base = Color("#5b5a50")
			speck = Color(0.78, 0.74, 0.62, 0.52)
			particle_count = 130
			max_radius = 3.4
		"planted_soil":
			base = Color("#3d3025")
			speck = Color(0.26, 0.19, 0.13, 0.58)
			particle_count = 120
			max_radius = 2.6
		"reef_sand":
			base = Color("#b5a982")
			speck = Color(0.98, 0.91, 0.72, 0.42)
			particle_count = 100
			max_radius = 1.9
	draw_rect(bed, base, true)
	for i in range(particle_count):
		var x := inner.position.x + fposmod(i * 47.0 + sin(i) * 19.0, inner.size.x)
		var y := bed.position.y + 8.0 + fposmod(i * 19.0, max(4.0, bed.size.y - 12.0))
		var radius := 0.9 + float(i % 5) * max_radius * 0.2
		draw_circle(Vector2(x, y), radius, speck)
	draw_line(Vector2(bed.position.x, bed.position.y), Vector2(bed.end.x, bed.position.y), Color(0.95, 0.90, 0.72, 0.18), 1.0, true)
	var maturity = state.get("maturity", {})
	var mulm := float(maturity.get("mulm", 0.0))
	var symptoms = state.get("symptoms", {})
	var detritus: float = clamp(float(symptoms.get("dirty_substrate", 0.0)), mulm, 1.0)
	if detritus > 0.04:
		for i in range(int(18 + detritus * 92.0)):
			var x := inner.position.x + fposmod(i * 53.0 + sin(i * 1.7) * 29.0, inner.size.x)
			var y := bed.position.y + 5.0 + fposmod(i * 23.0, max(5.0, bed.size.y * 0.45))
			draw_circle(Vector2(x, y), 1.2 + float(i % 4) * 0.6, Color(0.12, 0.095, 0.055, 0.10 + detritus * 0.22))

func _draw_water_seasoning(inner: Rect2) -> void:
	var maturity = state.get("maturity", {})
	var symptoms = state.get("symptoms", {})
	var biofilm := float(maturity.get("biofilm", 0.0))
	var microfauna := float(maturity.get("microfauna", 0.0))
	var visible_microfauna: float = max(microfauna, float(symptoms.get("visible_microfauna", 0.0)))
	var pest_snails := float(symptoms.get("pest_snails", maturity.get("pest_snails", 0.0)))
	var shock := float(maturity.get("last_water_change_shock", 0.0))
	if biofilm > 0.08:
		draw_rect(inner, Color(0.68, 0.82, 0.70, biofilm * 0.035), true)
	if shock > 0.04:
		draw_rect(inner, Color(0.86, 0.92, 0.72, shock * 0.12), true)
	if visible_microfauna > 0.16:
		for i in range(int(10 + visible_microfauna * 38.0)):
			var pos := Vector2(
				inner.position.x + fposmod(i * 89.0 + Time.get_ticks_msec() / 95.0, inner.size.x),
				inner.position.y + 48.0 + fposmod(i * 61.0 + sin(Time.get_ticks_msec() / 1300.0 + i) * 14.0, inner.size.y - SAND_HEIGHT - 88.0)
			)
			draw_circle(pos, 0.8 + float(i % 3) * 0.18, Color(0.88, 0.96, 0.84, 0.07 + visible_microfauna * 0.08))
	if pest_snails > 0.08:
		var count := int(4 + pest_snails * 24.0)
		var sand_top := inner.end.y - _substrate_height()
		for i in range(count):
			var x := inner.position.x + 24.0 + fposmod(i * 71.0, inner.size.x - 48.0)
			var y := sand_top - 6.0 - fposmod(i * 19.0, inner.size.y * 0.48)
			if i % 3 != 0:
				y = sand_top - 7.0 - float(i % 5) * 3.0
			var shell := Vector2(x, y)
			draw_arc(shell, 4.4, 0.1, TAU * 0.88, 14, Color(0.69, 0.57, 0.38, 0.18 + pest_snails * 0.22), 1.2, true)
			draw_circle(shell + Vector2(2.0, 1.2), 1.1, Color(0.35, 0.31, 0.22, 0.20 + pest_snails * 0.18))

func _aquascape_style() -> String:
	return str(state.get("aquarium", {}).get("aquascape_style", "greenscape"))

func _scape_items(category: String) -> Array:
	var scape = state.get("aquarium", {}).get("scape", {})
	var result := []
	if typeof(scape) == TYPE_DICTIONARY and scape.has(category):
		for item in scape.get(category, []):
			result.append(item)
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

func _scape_object_draw_size(category: String, item_type: String) -> Vector2:
	match item_type:
		"river_stone":
			return Vector2(96, 74)
		"moss_stone":
			return Vector2(112, 84)
		"dragon_stone":
			return Vector2(126, 96)
		"slate_stack":
			return Vector2(118, 88)
		"lava_rock", "live_rock":
			return Vector2(108, 84)
		"reef_arch":
			return Vector2(182, 132)
		"branch_driftwood", "manzanita_branch":
			return Vector2(190, 148)
		"root_driftwood":
			return Vector2(208, 164)
		"dwarf_hairgrass":
			return Vector2(110, 96)
		"vallisneria", "turtle_grass":
			return Vector2(108, 172)
		"amazon_sword", "hornwort":
			return Vector2(106, 132)
		"java_fern":
			return Vector2(96, 98)
		"anubias", "cryptocoryne_wendtii", "halimeda_macroalgae":
			return Vector2(86, 82)
		"java_moss":
			return Vector2(92, 66)
		"red_root_floaters":
			return Vector2(108, 78)
		"torch_coral", "kenya_tree_coral":
			return Vector2(108, 116)
		"zoanthids", "mushroom_coral", "green_star_polyps", "pulsing_xenia":
			return Vector2(94, 74)
	return Vector2(96, 88) if category != "wood" else Vector2(180, 140)

func _custom_scape_objects_for_layer(layer: int) -> Array:
	var scape = state.get("aquarium", {}).get("scape", {})
	var objects: Array = []
	if typeof(scape) != TYPE_DICTIONARY:
		return objects
	for value in scape.get("objects", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var obj: Dictionary = value
		if int(obj.get("layer", 1)) == layer:
			objects.append(obj)
	objects.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_y: float = float(left.get("y", 0.0))
		var right_y: float = float(right.get("y", 0.0))
		if not is_equal_approx(left_y, right_y):
			return left_y < right_y
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	return objects

func _draw_custom_scape_objects(layer: int) -> void:
	for obj in _custom_scape_objects_for_layer(layer):
		_draw_custom_scape_object(obj)

func _draw_custom_scape_object(obj: Dictionary) -> void:
	var category := str(obj.get("category", ""))
	var item_type := str(obj.get("type", ""))
	if category == "" or item_type == "":
		return
	var scale: float = clamp(float(obj.get("scale", 1.0)), 0.35, 2.4)
	var draw_size := _scape_object_draw_size(category, item_type) * scale
	var pos := _object_pos(obj, _tank_inner().get_center())
	var rotation: float = deg_to_rad(float(obj.get("rotation", 0.0)))
	var flip := bool(obj.get("flipped", false))
	var tint := Color.WHITE
	if category == "plants" or category == "corals":
		var health: float = clamp(float(obj.get("health", 0.86)), 0.0, 1.0)
		tint = Color.WHITE.lerp(Color("#8e7b4f"), 1.0 - health)
	if category in ["rocks", "wood", "corals"]:
		_draw_ellipse(pos + Vector2(8, draw_size.y * 0.16), draw_size.x * 0.32, max(5.0, draw_size.y * 0.09), Color(0.01, 0.02, 0.02, 0.19), true)
	if _draw_scape_sprite(item_type, pos, draw_size, flip, tint, rotation):
		return
	match category:
		"rocks":
			_draw_rock(pos, draw_size.x * 0.38, _rock_color(item_type), int(pos.x + pos.y))
		"wood":
			_draw_driftwood(pos + Vector2(0, draw_size.y * 0.28), 4, int(pos.x))
		"plants":
			_draw_rosette(int(pos.x), _tank_inner(), _tank_inner().end.y - _substrate_height(), Color("#5ca86c"), draw_size.y * 0.55)
		"corals":
			_draw_coral_fallback(item_type, pos, int(pos.y), 0.86)

func _scape_layer_color(layer: int) -> Color:
	match layer:
		0:
			return Color("#88b7df")
		2:
			return Color("#e2c56c")
		_:
			return Color("#78d2a1")

func _draw_scape_editor_overlay() -> void:
	var inner := _tank_inner()
	if selected_scape_object_id != "":
		var selected := _scape_object_by_id(selected_scape_object_id)
		if not selected.is_empty():
			var category := str(selected.get("category", ""))
			var item_type := str(selected.get("type", ""))
			var scale: float = clamp(float(selected.get("scale", 1.0)), 0.35, 2.4)
			var draw_size := _scape_object_draw_size(category, item_type) * scale
			var pos := _object_pos(selected, inner.get_center())
			var rotation: float = deg_to_rad(float(selected.get("rotation", 0.0)))
			var x_scale := -1.0 if bool(selected.get("flipped", false)) else 1.0
			var color := _scape_layer_color(int(selected.get("layer", 1)))
			draw_set_transform(pos, rotation, Vector2(x_scale, 1.0))
			var frame := Rect2(-draw_size * 0.5 - Vector2(6, 6), draw_size + Vector2(12, 12))
			draw_rect(frame, Color(color.r, color.g, color.b, 0.065), true)
			draw_rect(frame, Color(color.r, color.g, color.b, 0.82), false, 1.5, true)
			var handle := Vector2(0, -draw_size.y * 0.5 - 18.0)
			draw_line(Vector2(0, -draw_size.y * 0.5 - 6.0), handle, Color(color.r, color.g, color.b, 0.76), 1.4, true)
			draw_circle(handle, 4.5, Color(color.r, color.g, color.b, 0.9))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var pending: Dictionary = _scape_transform_values()
			var pending_scale: float = float(pending.get("scale", scale))
			var pending_rotation: float = deg_to_rad(float(pending.get("rotation", rad_to_deg(rotation))))
			var pending_layer: int = int(pending.get("layer", int(selected.get("layer", 1))))
			var pending_flip: bool = bool(pending.get("flipped", bool(selected.get("flipped", false))))
			var changed: bool = abs(pending_scale - scale) > 0.005 or abs(pending_rotation - rotation) > 0.002 or pending_layer != int(selected.get("layer", 1)) or pending_flip != bool(selected.get("flipped", false))
			if changed:
				var pending_size := _scape_object_draw_size(category, item_type) * pending_scale
				var pending_color := _scape_layer_color(pending_layer)
				draw_set_transform(pos, pending_rotation, Vector2(-1.0 if pending_flip else 1.0, 1.0))
				draw_rect(Rect2(-pending_size * 0.5 - Vector2(3, 3), pending_size + Vector2(6, 6)), Color(pending_color.r, pending_color.g, pending_color.b, 0.46), false, 1.0, true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if selected_scape_tool.is_empty():
		return
	var mouse := get_viewport().get_mouse_position()
	if not inner.has_point(mouse):
		return
	var category := str(selected_scape_tool.get("category", ""))
	var item_type := str(selected_scape_tool.get("type", ""))
	var normalized := Vector2(
		clamp((mouse.x - inner.position.x) / inner.size.x, 0.0, 1.0),
		clamp((mouse.y - inner.position.y) / inner.size.y, 0.0, 1.0)
	)
	var valid := _client_position_valid(category, item_type, normalized, true)
	var transform := _scape_transform_values()
	var scale: float = float(transform.get("scale", 1.0))
	var draw_size := _scape_object_draw_size(category, item_type) * scale
	var preview_color := Color(0.70, 0.94, 0.78, 0.80) if valid else Color(1.0, 0.42, 0.36, 0.68)
	if _draw_scape_sprite(item_type, mouse, draw_size, bool(transform.get("flipped", false)), Color(1, 1, 1, 0.58 if valid else 0.28), deg_to_rad(float(transform.get("rotation", 0.0)))):
		pass
	else:
		draw_circle(mouse, min(draw_size.x, draw_size.y) * 0.28, Color(preview_color.r, preview_color.g, preview_color.b, 0.34))
	draw_circle(mouse, max(draw_size.x, draw_size.y) * 0.42, preview_color, false, 1.6, true)

func _hit_scape_object(mouse: Vector2) -> String:
	var scape = state.get("aquarium", {}).get("scape", {})
	if typeof(scape) != TYPE_DICTIONARY:
		return ""
	var objects: Array = scape.get("objects", [])
	var best_id := ""
	var best_score := INF
	for layer in [2, 1, 0]:
		for index in range(objects.size() - 1, -1, -1):
			var obj: Dictionary = objects[index]
			if typeof(obj) != TYPE_DICTIONARY or int(obj.get("layer", 1)) != layer:
				continue
			var category := str(obj.get("category", ""))
			var item_type := str(obj.get("type", ""))
			var draw_size: Vector2 = _scape_object_draw_size(category, item_type) * clamp(float(obj.get("scale", 1.0)), 0.35, 2.4)
			var pos: Vector2 = _object_pos(obj, Vector2.ZERO)
			var local: Vector2 = (mouse - pos).rotated(-deg_to_rad(float(obj.get("rotation", 0.0))))
			var half_size := draw_size * 0.5 + Vector2(16.0, 16.0)
			var score := pow(local.x / max(1.0, half_size.x), 2.0) + pow(local.y / max(1.0, half_size.y), 2.0)
			if score <= 1.0 and score < best_score:
				best_score = score
				best_id = str(obj.get("id", ""))
	return best_id

func _rock_color(kind: String) -> Color:
	match kind:
		"moss_stone":
			return Color("#4f6752")
		"dragon_stone":
			return Color("#776b55")
		"slate_stack":
			return Color("#39434a")
		"lava_rock":
			return Color("#6a3b35")
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
		var polyp_extension: float = clamp(float(item.get("polyp_extension", 0.65)), 0.15, 1.0)
		var tissue_reserve: float = clamp(float(item.get("tissue_reserve", 0.68)), 0.0, 1.2)
		var visible_quantity: int = max(1, int(round(float(quantity) * lerp(0.35, 1.0, health))))
		for n in range(visible_quantity):
			var seed := coral_index + n + kind.length() * 3
			var pos := Vector2(
				inner.position.x + inner.size.x * (0.36 + fposmod(float(seed) * 0.117, 0.36)),
				sand_top - 8.0 + fposmod(float(seed) * 13.0, 28.0)
			)
			pos = _object_pos(item, pos)
			var draw_size: Vector2 = (Vector2(74, 58) if kind != "torch_coral" else Vector2(88, 92)) * lerp(0.42, 1.0, min(health, polyp_extension))
			var tint := Color.WHITE.lerp(Color("#ddd3bd") if bool(item.get("bleached", false)) else Color("#b79b82"), clamp(1.0 - min(health, tissue_reserve), 0.0, 1.0))
			if not _draw_scape_sprite(kind, pos, draw_size, seed % 2 == 0, tint):
				_draw_coral_fallback(kind, pos, seed, min(health, polyp_extension))
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

func _draw_scape_sprite(item_type: String, pos: Vector2, draw_size: Vector2, flip: bool = false, modulate: Color = Color.WHITE, rotation_offset: float = 0.0) -> bool:
	if not scape_textures.has(item_type):
		return false
	var texture: Texture2D = scape_textures[item_type]
	var living := PLANT_SCAPE_TYPES.has(item_type) or CORAL_SCAPE_TYPES.has(item_type)
	var t := Time.get_ticks_msec() / 1000.0
	var rotation := rotation_offset
	var draw_pos := pos
	var x_scale := -1.0 if flip else 1.0
	var y_scale := 1.0
	if living:
		var coral := CORAL_SCAPE_TYPES.has(item_type)
		var current: Vector2 = _water_current_at(pos)
		var current_strength: float = clamp(current.length() / 16.0, 0.0, 1.0)
		var sway := sin(t * (0.82 if coral else 1.08) + pos.x * 0.018 + pos.y * 0.011)
		if coral:
			rotation += sway * 0.016 * lerp(0.70, 1.55, current_strength)
		else:
			var stiffness: float = _plant_stiffness(item_type)
			var flow_bend: float = clamp(current.x / 15.0, -1.0, 1.0) * (0.028 + current_strength * 0.042) * stiffness
			rotation += flow_bend + sway * 0.018 * stiffness
			draw_pos += Vector2(current.x * (0.16 + stiffness * 0.22), sin(t * 0.72 + pos.x * 0.012) * current_strength * stiffness * 1.8)
		x_scale *= 1.0 + sin(t * 1.35 + pos.y * 0.017) * (0.007 if coral else 0.012) * lerp(0.70, 1.40, current_strength)
		y_scale = 1.0 + cos(t * 1.10 + pos.x * 0.013) * (0.010 if coral else 0.016) * lerp(0.70, 1.35, current_strength)
	draw_set_transform(draw_pos, rotation, Vector2(x_scale, y_scale))
	draw_texture_rect(texture, Rect2(-draw_size * 0.5, draw_size), false, modulate)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true

func _plant_stiffness(item_type: String) -> float:
	match item_type:
		"red_root_floaters":
			return 1.35
		"vallisneria", "hornwort":
			return 1.20
		"dwarf_hairgrass":
			return 0.92
		"java_moss", "anubias", "java_fern", "cryptocoryne_wendtii":
			return 0.42
		"amazon_sword":
			return 0.68
		_:
			return 0.72

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
	for item in _scape_items("plants"):
		var kind := str(item.get("type", "java_fern"))
		var quantity := int(item.get("quantity", 0))
		var health: float = clamp(float(item.get("health", 0.86)), 0.0, 1.0)
		var visible_quantity: int = max(1, int(round(float(quantity) * lerp(0.22, 1.0, health))))
		var tint := Color.WHITE.lerp(Color("#8e7b4f"), 1.0 - health)
		for n in range(visible_quantity):
			var seed := n + quantity * kind.length()
			match kind:
				"dwarf_hairgrass":
					var pos := Vector2(inner.position.x + fposmod(seed * 31.0, inner.size.x), sand_top + 17.0 + fposmod(seed * 17.0, 34.0))
					pos = _object_pos(item, pos)
					if not _draw_scape_sprite(kind, pos, Vector2(86, 86) * lerp(0.55, 1.0, health), seed % 2 == 0, tint):
						_draw_carpet_patch(seed, inner, sand_top, health)
				"vallisneria":
					var pos := Vector2(inner.position.x + 42.0 + fposmod(seed * 73.0, inner.size.x - 84.0), sand_top - 38.0)
					pos = _object_pos(item, pos)
					if not _draw_scape_sprite(kind, pos, Vector2(86, 132) * lerp(0.62, 1.0, health), seed % 2 == 0, tint):
						_draw_vallisneria(seed, inner, sand_top, health)
				"amazon_sword":
					var pos := _object_pos(item, Vector2(inner.position.x + 48.0 + fposmod(seed * 61.0, inner.size.x - 96.0), sand_top - 24.0))
					if not _draw_scape_sprite(kind, pos, Vector2(86, 104) * lerp(0.55, 1.0, health), seed % 2 == 0, tint):
						_draw_rosette(seed, inner, sand_top, Color("#4f9f64").lerp(Color("#8e7b4f"), 1.0 - health), 58.0 * lerp(0.45, 1.0, health))
				"cryptocoryne_wendtii":
					var pos := _object_pos(item, Vector2(inner.position.x + 48.0 + fposmod(seed * 53.0, inner.size.x - 96.0), sand_top - 10.0))
					if not _draw_scape_sprite(kind, pos, Vector2(70, 62) * lerp(0.55, 1.0, health), seed % 2 == 0, tint):
						_draw_rosette(seed, inner, sand_top, Color("#668d54").lerp(Color("#8e7b4f"), 1.0 - health), 32.0 * lerp(0.45, 1.0, health))
				"java_moss":
					var pos := _object_pos(item, Vector2(inner.position.x + 48.0 + fposmod(seed * 67.0, inner.size.x - 96.0), sand_top - 4.0))
					if not _draw_scape_sprite(kind, pos, Vector2(72, 54) * lerp(0.55, 1.0, health), seed % 2 == 0, tint):
						for puff in range(max(1, int(5 * health))):
							draw_circle(pos + Vector2(cos(puff * TAU / 5.0) * 12.0, sin(puff * TAU / 5.0) * 7.0), 11.0 * lerp(0.5, 1.0, health), Color("#5aaa63").lerp(Color("#8e7b4f"), 1.0 - health))
				"hornwort":
					var pos := _object_pos(item, Vector2(inner.position.x + 42.0 + fposmod(seed * 71.0, inner.size.x - 84.0), sand_top - 34.0))
					if not _draw_scape_sprite(kind, pos, Vector2(82, 112) * lerp(0.62, 1.0, health), seed % 2 == 0, tint):
						_draw_vallisneria(seed + 17, inner, sand_top, health)
				"java_fern":
					var pos := Vector2(inner.position.x + 48.0 + fposmod(seed * 59.0, inner.size.x - 96.0), sand_top - 18.0)
					pos = _object_pos(item, pos)
					if not _draw_scape_sprite(kind, pos, Vector2(78, 78) * lerp(0.55, 1.0, health), seed % 2 == 0, tint):
						_draw_rosette(seed, inner, sand_top, Color("#4f9c5c").lerp(Color("#8e7b4f"), 1.0 - health), 42.0 * lerp(0.45, 1.0, health))
				"anubias":
					var pos := Vector2(inner.position.x + 48.0 + fposmod(seed * 59.0, inner.size.x - 96.0), sand_top - 12.0)
					pos = _object_pos(item, pos)
					if not _draw_scape_sprite(kind, pos, Vector2(66, 66) * lerp(0.55, 1.0, health), seed % 2 == 0, tint):
						_draw_rosette(seed, inner, sand_top, Color("#3f8758").lerp(Color("#8e7b4f"), 1.0 - health), 30.0 * lerp(0.45, 1.0, health))
				"red_root_floaters":
					var pos := Vector2(inner.position.x + 44.0 + fposmod(seed * 67.0, inner.size.x - 88.0), inner.position.y + 46.0 + fposmod(seed * 11.0, 25.0))
					pos = _object_pos(item, pos)
					if not _draw_scape_sprite(kind, pos, Vector2(70, 70) * lerp(0.55, 1.0, health), seed % 2 == 0, tint):
						_draw_floaters(seed, inner, health)
				"halimeda_macroalgae":
					var pos := _object_pos(item, Vector2(inner.position.x + 48.0 + fposmod(seed * 59.0, inner.size.x - 96.0), sand_top - 16.0))
					if not _draw_scape_sprite(kind, pos, Vector2(76, 76) * lerp(0.55, 1.0, health), seed % 2 == 0, tint):
						_draw_rosette(seed, inner, sand_top, Color("#78ba70").lerp(Color("#8e7b4f"), 1.0 - health), 34.0 * lerp(0.45, 1.0, health))
				_:
					_draw_rosette(seed, inner, sand_top, Color("#5ca86c"), 34.0)

func _draw_carpet_patch(seed: int, inner: Rect2, sand_top: float, health: float = 1.0) -> void:
	var x := inner.position.x + fposmod(seed * 31.0, inner.size.x)
	var y := sand_top + 10.0 + fposmod(seed * 17.0, 46.0)
	var leaf := (Color("#5fbf73") if seed % 2 == 0 else Color("#7ad089")).lerp(Color("#8e7b4f"), 1.0 - health)
	_draw_leaf(Vector2(x, y), 12.0 * lerp(0.55, 1.0, health), 5.0 * lerp(0.55, 1.0, health), leaf)

func _draw_vallisneria(seed: int, inner: Rect2, sand_top: float, health: float = 1.0) -> void:
	var base_x := inner.position.x + 34.0 + fposmod(seed * 73.0, inner.size.x - 68.0)
	var height: float = (72.0 + float((seed * 29) % 96)) * lerp(0.48, 1.0, health)
	var base := Vector2(base_x, sand_top + 8.0)
	var flow: Vector2 = _water_current_at(base)
	var sway := sin(Time.get_ticks_msec() / 1200.0 + seed) * (8.0 + flow.length() * 0.9)
	for blade in range(max(1, int(ceil(4.0 * health)))):
		var offset := float(blade - 1) * 4.0
		var tip := base + Vector2(offset + sway * (0.45 + blade * 0.08), -height + blade * 13.0)
		draw_line(base + Vector2(offset, 0), tip, Color("#6cbd72").lerp(Color("#8e7b4f"), 1.0 - health), 3.0, true)

func _draw_rosette(seed: int, inner: Rect2, sand_top: float, color: Color, height: float) -> void:
	var base := Vector2(
		inner.position.x + 48.0 + fposmod(seed * 59.0, inner.size.x - 96.0),
		sand_top + 8.0 - fposmod(seed * 13.0, 26.0)
	)
	for leaf_index in range(7):
		var angle := -PI * 0.95 + float(leaf_index) * PI * 0.32
		var flow: Vector2 = _water_current_at(base)
		var tip := base + Vector2(cos(angle) * height * 0.58 + flow.x * 0.32, sin(angle) * height + flow.y * 0.12)
		draw_line(base, tip, color.darkened(0.08), 3.0, true)
		_draw_leaf(tip, 16.0, 7.0, color.lightened(float(leaf_index % 2) * 0.05))

func _draw_floaters(seed: int, inner: Rect2, health: float = 1.0) -> void:
	var base := Vector2(
		inner.position.x + 28.0 + fposmod(seed * 67.0, inner.size.x - 56.0),
		inner.position.y + 26.0 + fposmod(seed * 11.0, 28.0)
	)
	var flow: Vector2 = _water_current_at(base)
	base += Vector2(flow.x * 0.55, sin(Time.get_ticks_msec() / 1400.0 + seed) * 2.5)
	for leaf_index in range(max(1, int(ceil(4.0 * health)))):
		var pos := base + Vector2(cos(leaf_index * TAU / 4.0) * 9.0, sin(leaf_index * TAU / 4.0) * 4.0)
		_draw_leaf(pos, 12.0 * lerp(0.55, 1.0, health), 7.0 * lerp(0.55, 1.0, health), Color("#76b86a").lerp(Color("#8e7b4f"), 1.0 - health))
		draw_line(pos, pos + Vector2(3.0, (14.0 + leaf_index * 3.0) * health), Color("#c26163"), 1.1, true)

func _draw_bubbles() -> void:
	var inner := _tank_inner()
	for i in range(18):
		var speed := 16.0 + float(i % 6) * 5.0
		var x := inner.position.x + 42.0 + fposmod(i * 91.0, inner.size.x - 84.0)
		var y := inner.end.y - SAND_HEIGHT - fposmod(Time.get_ticks_msec() / 1000.0 * speed + i * 39.0, inner.size.y - 80.0)
		var radius := 2.2 + float(i % 4)
		draw_circle(Vector2(x, y), radius, Color(0.83, 0.98, 1.0, 0.12), false, 1.3, true)

func _draw_action_effects() -> void:
	for effect in action_effects:
		var kind := str(effect.get("kind", ""))
		var progress: float = clamp(float(effect.get("age", 0.0)) / max(0.1, float(effect.get("duration", 1.0))), 0.0, 1.0)
		match kind:
			"feed":
				_draw_feeding_effect(progress, int(effect.get("seed", 0)))
			"water_change":
				_draw_water_change_effect(progress)
			"weekly_maintenance":
				_draw_water_change_effect(progress)
				_draw_vacuum_effect(progress)
			"service_filter":
				_draw_filter_service_effect(progress)
			"remove_uneaten_food":
				_draw_remove_food_effect(progress)
			"scrape_algae":
				_draw_scrape_algae_effect(progress)
			"trim_plants":
				_draw_trim_plants_effect(progress)
			"top_off":
				_draw_top_off_effect(progress)
			"empty_skimmer_cup":
				_draw_empty_skimmer_effect(progress)
			"test_water":
				_draw_test_water_effect(progress)
			"dose_ammonia", "dose_minerals":
				_draw_dosing_effect(progress, kind)
			"set_substrate":
				_draw_substrate_settle_effect(progress)
			"add_animal":
				_draw_net_effect(progress, true, effect)
			"remove_animal":
				_draw_net_effect(progress, false, effect)
			"place_scape_item", "move_scape_item", "duplicate_scape_item", "remove_scape_item":
				_draw_scape_tool_effect(progress, kind, effect)
			"reset_scape", "clear_scape":
				_draw_scape_reset_effect(progress, kind)
			"set_equipment":
				_draw_equipment_adjust_effect(progress, effect)
			"switch_system":
				_draw_system_switch_effect(progress, effect)
			"create_aquarium", "select_aquarium":
				_draw_aquarium_card_effect(progress, kind, effect)
			"quarantine_animal":
				_draw_quarantine_effect(progress, effect)
			"treat_outbreak":
				_draw_treatment_effect(progress, effect)
			"install_safeguards":
				_draw_safeguards_effect(progress)

func _ease_out_cubic(value: float) -> float:
	var t: float = clamp(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)

func _ease_in_out_sine(value: float) -> float:
	var t: float = clamp(value, 0.0, 1.0)
	return -(cos(PI * t) - 1.0) * 0.5

func _effect_fade(progress: float) -> float:
	return clamp(min(progress / 0.16, (1.0 - progress) / 0.18), 0.0, 1.0)

func _effect_strength(effect: Dictionary) -> float:
	var progress: float = clamp(float(effect.get("age", 0.0)) / max(0.1, float(effect.get("duration", 1.0))), 0.0, 1.0)
	return sin(progress * PI) * _effect_fade(progress)

func _active_action_strength(kinds: Array) -> float:
	var strength := 0.0
	for effect in action_effects:
		if kinds.has(str(effect.get("kind", ""))):
			strength = max(strength, _effect_strength(effect))
	return strength

func _latest_action_effect(kinds: Array) -> Dictionary:
	var latest := {}
	var lowest_age := 999999.0
	for effect in action_effects:
		var kind := str(effect.get("kind", ""))
		if not kinds.has(kind):
			continue
		var age := float(effect.get("age", 0.0))
		if age < lowest_age:
			lowest_age = age
			latest = effect
	return latest

func _active_action_point(kinds: Array, fallback_ratio: Vector2) -> Vector2:
	var effect := _latest_action_effect(kinds)
	if effect.is_empty():
		var inner := _tank_inner()
		return inner.position + Vector2(inner.size.x * fallback_ratio.x, inner.size.y * fallback_ratio.y)
	return _effect_point(effect, fallback_ratio)

func _effect_point(effect: Dictionary, fallback: Vector2) -> Vector2:
	var inner := _tank_inner()
	var x: float = clamp(float(effect.get("x", fallback.x)), 0.04, 0.96)
	var y: float = clamp(float(effect.get("y", fallback.y)), 0.04, 0.94)
	return inner.position + Vector2(inner.size.x * x, inner.size.y * y)

func _draw_tool_handle(from_pos: Vector2, to_pos: Vector2, color: Color, width: float = 5.0) -> void:
	draw_line(from_pos, to_pos, Color(0.06, 0.08, 0.08, color.a * 0.45), width + 3.0, true)
	draw_line(from_pos, to_pos, color, width, true)

func _draw_water_rings(center: Vector2, progress: float, color: Color, count: int = 3, radius_step: float = 24.0) -> void:
	var fade := _effect_fade(progress)
	for r in range(count):
		var delay := float(r) * 0.12
		var p: float = clamp((progress - delay) / max(0.1, 1.0 - delay), 0.0, 1.0)
		if p <= 0.0:
			continue
		var radius := 10.0 + p * radius_step * float(r + 1)
		draw_arc(center, radius, 0.0, TAU, 56, Color(color.r, color.g, color.b, color.a * fade * (1.0 - p) * 0.8), 1.5, true)

func _draw_speck_cloud(center: Vector2, progress: float, seed: int, count: int, color: Color, spread: Vector2, drift: Vector2 = Vector2.ZERO) -> void:
	var fade := _effect_fade(progress)
	for i in range(count):
		var delay := float(i % 9) * 0.035
		var p: float = clamp((progress - delay) / max(0.1, 1.0 - delay), 0.0, 1.0)
		if p <= 0.0:
			continue
		var angle := float((i * 137 + seed * 19) % 360) * PI / 180.0
		var wobble := sin(progress * TAU * (0.6 + float(i % 5) * 0.08) + seed + i)
		var radius := (0.18 + fposmod(float(i * 31 + seed), 100.0) / 100.0) * p
		var pos := center + Vector2(cos(angle) * spread.x, sin(angle) * spread.y) * radius + drift * p + Vector2(wobble * 7.0, sin(i + progress * 7.0) * 3.0)
		var alpha := color.a * fade * (1.0 - p * 0.56)
		draw_circle(pos, 1.2 + float(i % 4) * 0.45, Color(color.r, color.g, color.b, alpha))

func _draw_ellipse(center: Vector2, radius_x: float, radius_y: float, color: Color, filled: bool = true, width: float = 1.0) -> void:
	var points := PackedVector2Array()
	for i in range(34):
		var angle := TAU * float(i) / 34.0
		points.push_back(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	if filled:
		var colors := PackedColorArray()
		for i in range(points.size()):
			colors.push_back(color)
		draw_polygon(points, colors)
	else:
		draw_polyline(points, color, width, true)

func _draw_feeding_effect(progress: float, seed: int) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var effect := _latest_action_effect(["feed"])
	var food_type := str(effect.get("food_type", "community_flake"))
	var drop_x := inner.position.x + inner.size.x * 0.36
	var pinch := Vector2(drop_x, inner.position.y - 4.0 + sin(progress * PI) * 10.0)
	draw_circle(pinch + Vector2(-22.0, -1.0), 13.0, Color(0.82, 0.62, 0.46, 0.70 * fade))
	draw_circle(pinch + Vector2(-7.0, 1.0), 8.0, Color(0.92, 0.72, 0.52, 0.76 * fade))
	_draw_water_rings(Vector2(drop_x, inner.position.y + 20.0), progress, Color(0.84, 0.96, 1.0, 0.20), 4, 26.0)
	var color := Color(0.94, 0.66, 0.30, 0.82)
	var count := 36
	var sink_depth := inner.size.y * 0.46
	var spread := 30.0
	var piece := "flake"
	match food_type:
		"micro_pellet":
			color = Color(0.82, 0.54, 0.26, 0.82)
			count = 46
			sink_depth = inner.size.y * 0.62
			spread = 24.0
			piece = "pellet"
		"sinking_wafer":
			color = Color(0.66, 0.46, 0.22, 0.86)
			count = 18
			sink_depth = inner.size.y - _substrate_height() - 34.0
			spread = 18.0
			piece = "wafer"
		"algae_wafer":
			color = Color(0.28, 0.62, 0.25, 0.84)
			count = 22
			sink_depth = inner.size.y - _substrate_height() - 30.0
			spread = 20.0
			piece = "wafer"
		"frozen_invertebrates":
			color = Color(0.86, 0.24, 0.20, 0.78)
			count = 32
			sink_depth = inner.size.y * 0.58
			spread = 34.0
			piece = "chunk"
		"reef_plankton":
			color = Color(1.00, 0.72, 0.48, 0.58)
			count = 72
			sink_depth = inner.size.y * 0.42
			spread = 58.0
			piece = "plankton"
	for i in range(count):
		var delay := float(i % 10) * 0.035
		var fall: float = clamp((progress - delay) / 0.82, 0.0, 1.0)
		if fall <= 0.0:
			continue
		var lateral := sin(float(i * 17 + seed)) * spread + sin(progress * 8.0 + i) * (7.0 + spread * 0.08)
		var drift := sin(progress * 2.4 + float(i)) * 20.0 * fall
		var x: float = drop_x + lateral + drift
		var y := inner.position.y + 22.0 + _ease_out_cubic(fall) * sink_depth
		var alpha: float = fade * clamp(1.0 - fall * 0.28, 0.0, 1.0)
		if piece == "wafer":
			_draw_ellipse(Vector2(x, y), 5.6 + float(i % 3), 2.4, Color(color.r, color.g, color.b, color.a * alpha), true)
			draw_line(Vector2(x - 4, y - 1), Vector2(x + 4, y + 1), Color(0.20, 0.13, 0.07, 0.28 * alpha), 1.0, true)
		elif piece == "flake":
			var flake := PackedVector2Array([
				Vector2(x - 3.0, y - 1.5),
				Vector2(x + 2.4, y - 3.0 + sin(i) * 1.2),
				Vector2(x + 4.0, y + 1.4),
				Vector2(x - 1.5, y + 3.0)
			])
			draw_polygon(flake, PackedColorArray([Color(color.r, color.g, color.b, color.a * alpha), color.lightened(0.12), color, color.darkened(0.08)]))
		elif piece == "plankton":
			draw_circle(Vector2(x, y), 0.9 + float(i % 3) * 0.25, Color(color.r, color.g, color.b, color.a * alpha))
		else:
			draw_circle(Vector2(x, y), 1.9 + float(i % 3) * 0.55, Color(color.r, color.g, color.b, color.a * alpha))
	if food_type in ["sinking_wafer", "algae_wafer", "reef_plankton"]:
		var target := Vector2(drop_x, inner.end.y - _substrate_height() - 24.0 if food_type != "reef_plankton" else inner.position.y + inner.size.y * 0.42)
		_draw_speck_cloud(target, progress, seed + 77, 34 if food_type == "reef_plankton" else 18, Color(color.r, color.g, color.b, 0.22), Vector2(78, 28), Vector2(28, -12))

func _draw_water_change_effect(progress: float) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var effect: Dictionary = _latest_action_effect(["water_change", "weekly_maintenance"])
	var disturbed: bool = bool(effect.get("disturbed_substrate", false)) or str(effect.get("kind", "")) == "weekly_maintenance"
	var fraction: float = clamp(float(effect.get("fraction", 0.25)), 0.05, 0.60)
	var drain_phase: float = clamp(progress / 0.46, 0.0, 1.0)
	var fill_phase: float = clamp((progress - 0.46) / 0.54, 0.0, 1.0)
	var water_drop: float = sin(progress * PI) * lerp(32.0, 72.0, fraction / 0.60)
	var line_y: float = inner.position.y + 18.0 + water_drop
	draw_rect(Rect2(inner.position.x + 18, inner.position.y + 18, inner.size.x - 36, max(4.0, water_drop)), Color(0.05, 0.10, 0.11, 0.18 * fade * sin(progress * PI)), true)
	draw_line(Vector2(inner.position.x + 18, line_y), Vector2(inner.end.x - 18, line_y), Color(0.88, 0.98, 1.0, 0.52 * fade), 3.0, true)
	_draw_water_rings(Vector2(inner.position.x + inner.size.x * 0.28, line_y), progress, Color(0.82, 0.96, 1.0, 0.16), 2, 30.0)
	var siphon_start := Vector2(inner.end.x - 80, inner.position.y + 16)
	var siphon_end := Vector2(inner.end.x - 34, inner.end.y - _substrate_height() - 22)
	_draw_tool_handle(siphon_start, siphon_end, Color(0.74, 0.84, 0.88, 0.86 * fade), 6.0)
	draw_circle(siphon_end, 9.0, Color(0.88, 0.96, 0.94, 0.18 * fade), false, 2.0, true)
	var bucket := Rect2(Vector2(inner.end.x + 14.0, inner.end.y - _substrate_height() - 84.0), Vector2(54, 48))
	draw_rect(bucket, Color(0.12, 0.15, 0.15, 0.76 * fade), true)
	draw_rect(bucket, Color(0.83, 0.92, 0.95, 0.45 * fade), false, 2.0, true)
	draw_rect(Rect2(bucket.position + Vector2(8, 27 - 16 * drain_phase), Vector2(38, 13 + 16 * drain_phase)), Color(0.56, 0.82, 0.94, 0.46 * fade), true)
	for i in range(22):
		var t := fposmod((drain_phase + fill_phase) * 2.4 + float(i) / 22.0, 1.0)
		var pos := siphon_start.lerp(siphon_end, t)
		draw_circle(pos, 2.0, Color(0.78, 0.95, 1.0, 0.48 * fade))
	if disturbed:
		_draw_speck_cloud(siphon_end, progress, 34, 38, Color(0.52, 0.38, 0.18, 0.34), Vector2(108, 48), Vector2(-24, -20))
	if progress > 0.46:
		var pour_start := Vector2(inner.position.x + 72.0, inner.position.y - 2.0)
		var pour_end := Vector2(inner.position.x + 108.0, inner.position.y + 36.0)
		_draw_tool_handle(pour_start, pour_end, Color(0.82, 0.93, 0.96, 0.78 * fade), 5.0)
		for i in range(10):
			var stream_pos := pour_end + Vector2(sin(i) * 7.0, fposmod(fill_phase * 92.0 + i * 9.0, 64.0))
			draw_circle(stream_pos, 2.0, Color(0.78, 0.94, 1.0, 0.42 * fade))
		_draw_water_rings(pour_end + Vector2(8, 34), fill_phase, Color(0.78, 0.94, 1.0, 0.22), 3, 22.0)

func _draw_vacuum_effect(progress: float) -> void:
	var inner := _tank_inner()
	var bed_y := inner.end.y - _substrate_height()
	var fade := _effect_fade(progress)
	var sweep: float = _ease_in_out_sine(fposmod(progress * 1.25, 1.0))
	var x: float = lerp(inner.position.x + 88.0, inner.end.x - 132.0, sweep)
	_draw_tool_handle(Vector2(x, inner.position.y + inner.size.y * 0.38), Vector2(x + 36, bed_y + 10), Color(0.82, 0.87, 0.82, 0.78 * fade), 5.0)
	var bell := Rect2(Vector2(x + 20, bed_y - 24), Vector2(42, 46))
	draw_rect(bell, Color(0.90, 0.96, 0.90, 0.15 * fade), false, 2.0, true)
	draw_rect(Rect2(bell.position + Vector2(4, bell.size.y - 9), Vector2(bell.size.x - 8, 7)), Color(0.56, 0.43, 0.24, 0.18 * fade), true)
	for i in range(24):
		var sucked: float = clamp(progress * 1.35 - float(i % 8) * 0.045, 0.0, 1.0)
		var start: Vector2 = Vector2(x + 18 + fposmod(i * 11.0, 54.0), bed_y - 4 - fposmod(i * 17.0, 36.0))
		var pos: Vector2 = start.lerp(Vector2(x + 40, bed_y - 48.0), sucked)
		draw_circle(pos, 1.4 + float(i % 3) * 0.3, Color(0.42, 0.31, 0.18, 0.36 * fade * (1.0 - sucked * 0.45)))

func _draw_filter_service_effect(progress: float) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var pos := Vector2(inner.end.x - 164, inner.end.y - _substrate_height() - 110)
	draw_rect(Rect2(pos, Vector2(74, 86)), Color(0.07, 0.11, 0.12, 0.82 * fade), true)
	draw_rect(Rect2(pos, Vector2(74, 86)), Color(0.60, 0.82, 0.82, 0.36 * fade), false, 1.4, true)
	var lift := sin(progress * PI) * 34.0
	var cartridge := Rect2(pos + Vector2(16, 28 - lift), Vector2(42, 34))
	draw_rect(cartridge, Color(0.24, 0.38, 0.34, 0.78 * fade), true)
	draw_rect(cartridge, Color(0.78, 0.96, 0.88, 0.40 * fade), false, 1.2, true)
	for slot in range(4):
		draw_line(cartridge.position + Vector2(7, 8 + slot * 6), cartridge.position + Vector2(cartridge.size.x - 7, 8 + slot * 6), Color(0.12, 0.22, 0.20, 0.46 * fade), 1.3, true)
	for i in range(8):
		var y := pos.y + 18 + i * 8
		var pulse := sin(progress * TAU * 3.0 + i) * 0.5 + 0.5
		draw_line(Vector2(pos.x - 16 - pulse * 16.0, y), Vector2(pos.x + 58 + pulse * 12, y), Color(0.62, 0.92, 1.0, 0.34 * fade), 2.0, true)
	_draw_speck_cloud(cartridge.get_center(), progress, 241, 26, Color(0.55, 0.72, 0.62, 0.24), Vector2(70, 45), Vector2(-38, -12))

func _draw_remove_food_effect(progress: float) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var bed_y := inner.end.y - _substrate_height()
	var tip := Vector2(lerp(inner.position.x + inner.size.x * 0.28, inner.position.x + inner.size.x * 0.62, _ease_in_out_sine(progress)), bed_y - 24.0)
	_draw_tool_handle(tip + Vector2(-44, -72), tip, Color(0.78, 0.88, 0.84, 0.78 * fade), 5.0)
	draw_circle(tip + Vector2(-48, -80), 14.0, Color(0.45, 0.58, 0.52, 0.35 * fade), false, 3.0, true)
	draw_circle(tip, 9.0, Color(0.86, 0.94, 0.88, 0.20 * fade), false, 2.0, true)
	for i in range(22):
		var crumb := Vector2(tip.x + sin(i * 2.1) * (26.0 - progress * 18.0), bed_y - 8.0 - float(i % 4) * 4.0)
		var sucked := crumb.lerp(tip + Vector2(-12, -12), clamp(progress * 1.65 - float(i % 9) * 0.055, 0.0, 1.0))
		draw_circle(sucked, 1.4 + float(i % 3) * 0.35, Color(0.76, 0.47, 0.20, 0.58 * fade * (1.0 - progress * 0.58)))
	for ring in range(2):
		draw_arc(tip, 18.0 + ring * 14.0 + progress * 18.0, PI * 0.65, PI * 1.35, 22, Color(0.78, 0.94, 1.0, 0.10 * fade), 1.2, true)

func _draw_scrape_algae_effect(progress: float) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var x: float = lerp(inner.position.x + 36.0, inner.end.x - 96.0, _ease_in_out_sine(progress))
	var top := inner.position.y + 68.0
	var bottom := inner.end.y - _substrate_height() - 32.0
	var blade := Rect2(Vector2(x, top + sin(progress * TAU) * 8.0), Vector2(18, 92))
	draw_rect(Rect2(inner.position + Vector2(26, 54), Vector2(max(0.0, x - inner.position.x - 26.0), inner.size.y - _substrate_height() - 94)), Color(0.82, 0.96, 0.90, 0.055 * fade), true)
	draw_rect(Rect2(Vector2(x + 18, top), Vector2(44, bottom - top)), Color(0.18, 0.46, 0.16, 0.045 * fade), true)
	_draw_tool_handle(blade.position + Vector2(9, -44), blade.position + Vector2(9, 8), Color(0.72, 0.80, 0.76, 0.82 * fade), 4.0)
	draw_rect(blade, Color(0.87, 0.94, 0.90, 0.72 * fade), true)
	draw_rect(Rect2(blade.position + Vector2(3, 5), Vector2(12, 82)), Color(0.58, 0.68, 0.62, 0.42 * fade), false, 1.0, true)
	draw_line(Vector2(x + 18, top - 18), Vector2(x + 18, bottom), Color(0.96, 1.0, 0.96, 0.24 * fade), 2.0, true)
	for i in range(18):
		var fall: float = clamp(progress * 1.25 - float(i % 6) * 0.06, 0.0, 1.0)
		draw_circle(Vector2(x + 14 + sin(i) * 9.0, top + 20 + i * 10.0 + fall * 24.0), 1.5 + float(i % 3) * 0.35, Color(0.36, 0.70, 0.28, 0.38 * fade * (1.0 - fall * 0.35)))

func _draw_trim_plants_effect(progress: float) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var bed_y := inner.end.y - _substrate_height()
	var target := Vector2(inner.position.x + inner.size.x * 0.36, bed_y - 86.0)
	var open_amount := sin(progress * TAU * 3.0) * 8.0
	_draw_tool_handle(target + Vector2(-84, -54), target + Vector2(-8, -4), Color(0.72, 0.76, 0.78, 0.78 * fade), 4.0)
	draw_line(target, target + Vector2(46, -18 - open_amount), Color(0.88, 0.92, 0.92, 0.72 * fade), 3.0, true)
	draw_line(target, target + Vector2(45, 18 + open_amount), Color(0.88, 0.92, 0.92, 0.72 * fade), 3.0, true)
	draw_circle(target + Vector2(28, 0), 8.0, Color(0.88, 0.96, 0.90, 0.10 * fade), false, 1.5, true)
	for i in range(20):
		var drift: float = clamp(progress * 1.15 - float(i % 7) * 0.05, 0.0, 1.0)
		var leaf: Vector2 = target + Vector2(28 + sin(i) * 34.0 + drift * 18.0, 12 + fposmod(progress * 54.0 + i * 11.0, 62.0) - drift * 20.0)
		draw_line(leaf, leaf + Vector2(8 + sin(i), 4 + cos(i)), Color(0.34, 0.76, 0.30, 0.50 * fade * (1.0 - drift * 0.28)), 2.0, true)

func _draw_top_off_effect(progress: float) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var reservoir := Rect2(Vector2(inner.position.x + 48.0, inner.position.y - 36.0 + sin(progress * PI) * 5.0), Vector2(62, 34))
	draw_rect(reservoir, Color(0.70, 0.86, 0.92, 0.26 * fade), true)
	draw_rect(reservoir, Color(0.92, 0.98, 1.0, 0.56 * fade), false, 1.4, true)
	var tube_start := reservoir.position + Vector2(reservoir.size.x, 18)
	var tube_end := Vector2(inner.position.x + 132.0, inner.position.y + 28.0)
	_draw_tool_handle(tube_start, tube_end, Color(0.82, 0.92, 0.94, 0.66 * fade), 3.0)
	for i in range(16):
		var y := inner.position.y + 20.0 + fposmod(progress * 120.0 + i * 8.0, 72.0)
		draw_circle(Vector2(tube_end.x + sin(i) * 4.0, y), 1.6, Color(0.75, 0.94, 1.0, 0.46 * fade))
	_draw_water_rings(tube_end + Vector2(0, 54), progress, Color(0.76, 0.94, 1.0, 0.21), 3, 24.0)
	draw_line(Vector2(inner.position.x + 22.0, inner.position.y + 20.0), Vector2(inner.end.x - 22.0, inner.position.y + 20.0 - sin(progress * PI) * 5.0), Color(0.85, 0.97, 1.0, 0.30 * fade), 2.0, true)

func _draw_empty_skimmer_effect(progress: float) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var pos := Vector2(inner.end.x - 132.0, inner.position.y + 62.0)
	var body := Rect2(pos, Vector2(42, 72))
	draw_rect(body, Color(0.16, 0.19, 0.20, 0.64 * fade), true)
	draw_rect(body, Color(0.76, 0.90, 0.94, 0.24 * fade), false, 1.2, true)
	var cup := Rect2(pos + Vector2(7, 7 - sin(progress * PI) * 20.0), Vector2(28, 34))
	draw_rect(cup, Color(0.24, 0.19, 0.15, 0.70 * fade), true)
	draw_rect(Rect2(cup.position + Vector2(4, 8), Vector2(20, 15)), Color(0.42, 0.24, 0.11, 0.76 * fade * (1.0 - progress * 0.70)), true)
	var tilt := sin(progress * PI)
	draw_line(cup.position + Vector2(24, 10), cup.position + Vector2(68 + tilt * 22.0, -20 + tilt * 18.0), Color(0.52, 0.30, 0.14, 0.62 * fade), 4.0, true)
	for i in range(12):
		draw_circle(pos + Vector2(54 + float(i) * 4.5, -12.0 + float(i % 4) * 5.0 + progress * 24.0), 1.7 + float(i % 2) * 0.5, Color(0.42, 0.25, 0.13, 0.38 * fade))
	for b in range(12):
		var rise := fposmod(progress * 1.5 + float(b) * 0.13, 1.0)
		draw_circle(body.position + Vector2(10 + sin(b) * 12.0, body.size.y - rise * body.size.y), 1.2 + float(b % 3) * 0.3, Color(0.88, 0.98, 1.0, 0.20 * fade * (1.0 - rise * 0.4)))

func _draw_test_water_effect(progress: float) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var pos := Vector2(inner.position.x + inner.size.x * 0.58, inner.position.y + 50)
	_draw_tool_handle(pos + Vector2(-26, -34), pos + Vector2(0, 22), Color(0.92, 0.96, 0.92, 0.66 * fade), 3.0)
	var fill: float = clamp((progress - 0.2) / 0.45, 0.0, 1.0)
	var vial := Rect2(pos + Vector2(-12, 16), Vector2(24, 46))
	draw_rect(vial, Color(0.36, 0.78, 0.74, (0.12 + 0.30 * fill) * fade), true)
	draw_rect(vial, Color(0.90, 0.96, 0.92, 0.62 * fade), false, 1.2, true)
	draw_line(vial.position + Vector2(4, 8 + 22 * (1.0 - fill)), vial.position + Vector2(vial.size.x - 4, 8 + 22 * (1.0 - fill)), Color(0.94, 1.0, 0.96, 0.42 * fade), 1.0, true)
	draw_circle(pos + Vector2(0, lerp(-10.0, 22.0, progress)), 4.0, Color(0.80, 0.94, 1.0, 0.70 * fade))
	var strip := Rect2(pos + Vector2(36, 14), Vector2(52, 12))
	draw_rect(Rect2(strip.position + Vector2(-5, -6), Vector2(strip.size.x + 10, 62)), Color(0.92, 0.84, 0.62, 0.20 * fade), true)
	for i in range(4):
		var react: float = clamp((progress - 0.18 - float(i) * 0.06) / 0.62, 0.0, 1.0)
		var swatch: Color = Color.from_hsv(0.10 + float(i) * 0.16 + react * 0.08, 0.42 + react * 0.25, 0.78 + react * 0.12, 0.62 * fade)
		draw_rect(Rect2(strip.position + Vector2(0, i * 13), strip.size), swatch, true)
		draw_rect(Rect2(strip.position + Vector2(0, i * 13), strip.size), Color(0.26, 0.19, 0.12, 0.26 * fade), false, 1.0, true)

func _draw_dosing_effect(progress: float, kind: String) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var dropper := Vector2(inner.position.x + inner.size.x * 0.50, inner.position.y + 28)
	var dose_color := Color(0.93, 0.66, 0.26, 0.64)
	if kind == "dose_minerals":
		dose_color = Color(0.56, 0.84, 1.0, 0.60)
	_draw_tool_handle(dropper + Vector2(-24, -10), dropper + Vector2(24, -10), Color(0.86, 0.90, 0.88, 0.75 * fade), 5.0)
	draw_rect(Rect2(dropper + Vector2(-18, -34), Vector2(36, 20)), dose_color.darkened(0.25), true)
	draw_rect(Rect2(dropper + Vector2(-18, -34), Vector2(36, 20)), Color(1, 1, 1, 0.32 * fade), false, 1.0, true)
	for i in range(12):
		var y := dropper.y + fposmod(progress * 160.0 + i * 23.0, inner.size.y * 0.45)
		draw_circle(Vector2(dropper.x + sin(i) * 16.0, y), 2.2 + float(i % 3) * 0.5, Color(dose_color.r, dose_color.g, dose_color.b, 0.56 * fade))
	for r in range(4):
		draw_circle(dropper + Vector2(sin(r) * 18.0, inner.size.y * 0.26 + r * 12.0), 18.0 + progress * 44.0 + r * 10.0, Color(dose_color.r, dose_color.g, dose_color.b, 0.035 * fade * (1.0 - r * 0.12)))
	var cloud_center := dropper + Vector2(0, inner.size.y * 0.35)
	_draw_speck_cloud(cloud_center, progress, 177 if kind == "dose_minerals" else 121, 34, Color(dose_color.r, dose_color.g, dose_color.b, 0.22), Vector2(92, 54), Vector2(30, 18))

func _draw_substrate_settle_effect(progress: float) -> void:
	var inner := _tank_inner()
	var bed_y := inner.end.y - _substrate_height()
	var fade := _effect_fade(progress)
	var rake_x: float = lerp(inner.position.x + 76.0, inner.end.x - 142.0, _ease_in_out_sine(progress))
	_draw_tool_handle(Vector2(rake_x - 60.0, bed_y - 80.0), Vector2(rake_x, bed_y - 8.0), Color(0.72, 0.60, 0.42, 0.72 * fade), 4.0)
	for tooth in range(5):
		draw_line(Vector2(rake_x + tooth * 8.0, bed_y - 12.0), Vector2(rake_x + tooth * 8.0, bed_y + 6.0), Color(0.82, 0.68, 0.46, 0.58 * fade), 1.4, true)
	for i in range(44):
		var x := inner.position.x + fposmod(i * 31.0, inner.size.x)
		var y := bed_y - fposmod((1.0 - progress) * 82.0 + i * 13.0, 78.0)
		draw_circle(Vector2(x, y), 1.5 + float(i % 3), Color(0.72, 0.58, 0.36, 0.28 * fade * (1.0 - progress)))
	for ripple in range(4):
		var x0 := inner.position.x + 28.0
		var y0 := bed_y + 4.0 + ripple * 8.0
		var points := PackedVector2Array()
		for p in range(30):
			var x := x0 + float(p) * (inner.size.x - 56.0) / 29.0
			points.push_back(Vector2(x, y0 + sin(progress * TAU * 2.0 + p * 0.55 + ripple) * 2.0 * (1.0 - progress)))
		draw_polyline(points, Color(0.95, 0.86, 0.58, 0.16 * fade * (1.0 - progress)), 1.4, true)
	draw_line(Vector2(inner.position.x + 16, bed_y), Vector2(inner.end.x - 16, bed_y), Color(0.95, 0.86, 0.58, 0.28 * fade * (1.0 - progress)), 3.0, true)

func _draw_action_animal(species_id: String, pos: Vector2, facing: float, alpha: float) -> void:
	if fish_textures.has(species_id):
		var texture: Texture2D = fish_textures[species_id]
		var draw_size := _fish_sprite_size(species_id) * 0.78
		draw_set_transform(pos, sin(Time.get_ticks_msec() / 240.0) * 0.04, Vector2(1.0 if facing >= 0 else -1.0, 1.0))
		draw_texture_rect(texture, Rect2(-draw_size * 0.5, draw_size), false, Color(1, 1, 1, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	_draw_ellipse(pos, 14.0, 5.0, Color(0.96, 0.42, 0.32, 0.70 * alpha), true)
	draw_polygon(PackedVector2Array([pos + Vector2(-12 * facing, 0), pos + Vector2(-22 * facing, -7), pos + Vector2(-22 * facing, 7)]), PackedColorArray([Color(0.96, 0.42, 0.32, 0.62 * alpha), Color(0.96, 0.42, 0.32, 0.62 * alpha), Color(0.96, 0.42, 0.32, 0.62 * alpha)]))

func _draw_net_effect(progress: float, adding: bool, effect: Dictionary) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var target := _effect_point(effect, Vector2(0.52, 0.42))
	var entry := Vector2(inner.end.x + 80.0, inner.position.y + 42.0)
	var exit := Vector2(inner.position.x + 60.0, inner.position.y - 54.0)
	var travel: float = _ease_in_out_sine(progress)
	var net_pos := entry.lerp(target, min(travel * 1.5, 1.0)) if adding else target.lerp(exit, max(0.0, (travel - 0.18) / 0.82))
	var species_id := str(effect.get("species_id", ""))
	var acclimation := int(effect.get("acclimation_minutes", 0))
	if adding and acclimation > 0 and progress < 0.48:
		var bag_pos := Vector2(target.x - 24.0, inner.position.y + 34.0 + sin(progress * PI * 2.0) * 5.0)
		draw_rect(Rect2(bag_pos - Vector2(24, 18), Vector2(48, 40)), Color(0.82, 0.95, 1.0, 0.16 * fade), true)
		draw_rect(Rect2(bag_pos - Vector2(24, 18), Vector2(48, 40)), Color(0.92, 1.0, 1.0, 0.38 * fade), false, 1.2, true)
		_draw_action_animal(species_id, bag_pos + Vector2(0, 4), 1.0, 0.55 * fade)
	_draw_tool_handle(net_pos + Vector2(42.0, -46.0), net_pos + Vector2(6.0, -4.0), Color(0.72, 0.78, 0.75, 0.72 * fade), 4.0)
	draw_arc(net_pos, 24.0, -PI * 0.22, PI * 1.22, 28, Color(0.86, 0.96, 0.94, 0.62 * fade), 2.0, true)
	draw_line(net_pos + Vector2(-22, 0), net_pos + Vector2(22, 0), Color(0.86, 0.96, 0.94, 0.45 * fade), 1.4, true)
	for i in range(5):
		draw_line(net_pos + Vector2(-18 + i * 9.0, -16), net_pos + Vector2(-12 + i * 6.0, 16), Color(0.86, 0.96, 0.94, 0.20 * fade), 1.0, true)
	var fish_t: float = clamp((progress - 0.34) / 0.42, 0.0, 1.0)
	var fish_alpha: float = fade * (fish_t if adding else 1.0 - fish_t)
	var fish_pos := target + Vector2(sin(progress * TAU * 2.0) * 12.0, cos(progress * TAU) * 4.0)
	_draw_action_animal(species_id, fish_pos, 1.0 if adding else -1.0, fish_alpha)
	_draw_water_rings(target, progress, Color(0.80, 0.95, 1.0, 0.20), 3, 24.0)
	if adding and acclimation <= 0:
		draw_arc(target, 42.0 + sin(progress * TAU * 2.0) * 5.0, 0.0, TAU, 44, Color(1.0, 0.34, 0.28, 0.18 * fade), 2.0, true)

func _draw_scape_tool_effect(progress: float, kind: String, effect: Dictionary) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var target := _effect_point(effect, Vector2(0.50, 0.76))
	var hand := target + Vector2(-58.0 + sin(progress * PI) * 18.0, -96.0)
	_draw_tool_handle(hand, target + Vector2(-8, -6), Color(0.74, 0.68, 0.60, 0.72 * fade), 5.0)
	draw_line(hand + Vector2(-10, 10), target + Vector2(12, 4), Color(0.80, 0.76, 0.68, 0.56 * fade), 2.0, true)
	var item_color := Color(0.46, 0.36, 0.26, 0.72 * fade)
	if str(effect.get("category", "")) == "plants":
		item_color = Color(0.25, 0.68, 0.28, 0.72 * fade)
	elif str(effect.get("category", "")) == "rocks":
		item_color = Color(0.50, 0.50, 0.46, 0.72 * fade)
	elif str(effect.get("category", "")) == "corals":
		item_color = Color(0.93, 0.54, 0.62, 0.72 * fade)
	var lift := sin(progress * PI) * 28.0
	var item_pos := target - Vector2(0, lift)
	if kind == "remove_scape_item":
		item_pos = target.lerp(hand, _ease_out_cubic(progress))
		item_color.a *= 1.0 - progress * 0.55
	var item_type := str(effect.get("type", ""))
	if item_type != "" and scape_textures.has(item_type):
		var size := Vector2(54, 54)
		if str(effect.get("category", "")) in ["wood", "rocks"]:
			size = Vector2(72, 58)
		elif str(effect.get("category", "")) == "plants":
			size = Vector2(62, 72)
		_draw_scape_sprite(item_type, item_pos, size, bool(effect.get("flipped", int(effect.get("seed", 0)) % 2 == 0)), Color(1, 1, 1, clamp(item_color.a, 0.0, 1.0)), deg_to_rad(float(effect.get("rotation", 0.0))))
	else:
		draw_circle(item_pos, 18.0, item_color)
		draw_circle(item_pos + Vector2(-5, -5), 6.0, item_color.lightened(0.22))
	_draw_speck_cloud(target + Vector2(0, 8), progress, int(effect.get("seed", 0)) + 11, 18, Color(0.62, 0.48, 0.25, 0.20), Vector2(48, 22), Vector2(10, -10))
	_draw_water_rings(target, progress, Color(0.78, 0.94, 1.0, 0.13), 2, 20.0)
	if kind == "move_scape_item":
		draw_line(target + Vector2(-54, 24), target + Vector2(54, 24), Color(0.84, 0.95, 1.0, 0.26 * fade), 2.0, true)
		draw_circle(target + Vector2(-54, 24), 5.0, Color(0.84, 0.95, 1.0, 0.30 * fade), false, 1.4, true)
	elif kind == "duplicate_scape_item":
		var twin := target + Vector2(36.0, 22.0)
		draw_circle(twin, 20.0 + sin(progress * PI) * 6.0, Color(0.80, 0.95, 1.0, 0.12 * fade), false, 1.4, true)
		draw_line(target + Vector2(14, 10), twin - Vector2(12, 8), Color(0.84, 0.95, 1.0, 0.30 * fade), 1.4, true)

func _draw_scape_reset_effect(progress: float, kind: String) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var bed_y := inner.end.y - _substrate_height()
	var sweep_x: float = lerp(inner.position.x - 40.0, inner.end.x + 40.0, _ease_in_out_sine(progress))
	draw_rect(Rect2(Vector2(sweep_x - 46, inner.position.y + 34), Vector2(38, inner.size.y - _substrate_height() - 36)), Color(0.90, 0.96, 0.92, 0.13 * fade), true)
	for i in range(14):
		var pos := Vector2(sweep_x - 34.0 + sin(i) * 18.0, bed_y - 12.0 - fposmod(i * 15.0 + progress * 42.0, 88.0))
		draw_circle(pos, 2.0 + float(i % 3), Color(0.50, 0.42, 0.32, 0.24 * fade))
	if kind == "reset_scape":
		draw_rect(Rect2(inner.position + Vector2(28, 38), Vector2(inner.size.x - 56, inner.size.y - _substrate_height() - 70)), Color(0.76, 0.90, 1.0, 0.055 * fade), false, 1.2, true)
		for i in range(6):
			var sprout := Vector2(inner.position.x + inner.size.x * (0.20 + float(i) * 0.105), bed_y - 8.0)
			var h := sin(progress * PI) * (24.0 + float(i % 3) * 12.0)
			draw_line(sprout, sprout + Vector2(sin(i) * 7.0, -h), Color(0.42, 0.82, 0.42, 0.42 * fade), 2.2, true)
	else:
		draw_rect(Rect2(inner.position + Vector2(24, 32), Vector2(inner.size.x - 48, inner.size.y - _substrate_height() - 58)), Color(0.07, 0.10, 0.10, 0.10 * fade * progress), true)

func _draw_equipment_adjust_effect(progress: float, effect: Dictionary) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var equipment := str(effect.get("equipment", effect.get("target", ""))).to_lower()
	var pos := Vector2(inner.end.x - 98.0, inner.position.y + 72.0)
	if "light" in equipment:
		pos = Vector2(inner.position.x + inner.size.x * 0.5, inner.position.y + 12.0)
	elif "heater" in equipment:
		pos = Vector2(inner.end.x - 70.0, inner.end.y - _substrate_height() - 118.0)
	elif "air" in equipment:
		pos = Vector2(inner.position.x + 74.0, inner.end.y - _substrate_height() - 70.0)
	_draw_tool_handle(pos + Vector2(58, -44), pos + Vector2(8, 4), Color(0.78, 0.80, 0.76, 0.74 * fade), 4.0)
	draw_circle(pos, 24.0 + sin(progress * TAU * 2.0) * 4.0, Color(0.84, 0.95, 1.0, 0.10 * fade), false, 2.0, true)
	if "light" in equipment:
		draw_rect(Rect2(pos + Vector2(-96, -6), Vector2(192, 8)), Color(0.92, 0.98, 1.0, 0.30 * fade), true)
		draw_polygon(PackedVector2Array([pos + Vector2(-84, 6), pos + Vector2(84, 6), pos + Vector2(150, inner.size.y * 0.38), pos + Vector2(-150, inner.size.y * 0.38)]), PackedColorArray([Color(0.94, 0.98, 1.0, 0.08 * fade), Color(0.94, 0.98, 1.0, 0.08 * fade), Color(0.94, 0.98, 1.0, 0.00), Color(0.94, 0.98, 1.0, 0.00)]))
	elif "heater" in equipment:
		for i in range(5):
			var y := pos.y - 38 + i * 18
			draw_line(Vector2(pos.x - 12 + sin(progress * TAU + i) * 5.0, y), Vector2(pos.x + 14 + sin(progress * TAU + i + 0.8) * 5.0, y - 10), Color(1.0, 0.42, 0.26, 0.18 * fade), 1.5, true)
	elif "air" in equipment:
		for i in range(18):
			var rise := fposmod(progress * 1.6 + float(i) * 0.075, 1.0)
			draw_circle(pos + Vector2(sin(i) * 16.0, -rise * 128.0), 1.5 + float(i % 3) * 0.4, Color(0.82, 0.97, 1.0, 0.32 * fade * (1.0 - rise * 0.35)))
	else:
		for i in range(5):
			draw_line(pos + Vector2(6, -18 + i * 10), pos + Vector2(-72 - progress * 34.0, -22 + i * 9 + sin(i + progress * 8.0) * 5.0), Color(0.78, 0.94, 1.0, 0.18 * fade), 1.5, true)

func _draw_system_switch_effect(progress: float, effect: Dictionary) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var system := str(effect.get("system", "")).to_lower()
	var target_color := Color(0.44, 0.72, 0.88, 0.10 * fade)
	if system == "freshwater":
		target_color = Color(0.46, 0.78, 0.60, 0.10 * fade)
	var wipe_width := inner.size.x * _ease_in_out_sine(progress)
	draw_rect(Rect2(inner.position, Vector2(wipe_width, inner.size.y)), target_color, true)
	var front_x := inner.position.x + wipe_width
	draw_line(Vector2(front_x, inner.position.y + 24), Vector2(front_x, inner.end.y - _substrate_height()), Color(0.92, 0.98, 1.0, 0.24 * fade), 3.0, true)
	for i in range(26):
		var pos := Vector2(inner.position.x + fposmod(progress * inner.size.x * 1.4 + i * 58.0, inner.size.x), inner.position.y + 42.0 + fposmod(i * 31.0, inner.size.y - _substrate_height() - 72.0))
		var color := Color(0.92, 0.92, 1.0, 0.18 * fade)
		if system == "freshwater":
			color = Color(0.74, 0.92, 0.72, 0.18 * fade)
		if system == "saltwater":
			draw_line(pos + Vector2(-4, 0), pos + Vector2(4, 0), color, 1.1, true)
			draw_line(pos + Vector2(0, -4), pos + Vector2(0, 4), color, 1.1, true)
		else:
			draw_circle(pos, 2.0 + float(i % 4), color)
	for band in range(3):
		_draw_wave(Vector2(inner.position.x + 18, inner.position.y + 62 + band * 48), inner.size.x - 36, Color(target_color.r, target_color.g, target_color.b, 0.18 * fade), progress * 8.0 + band)

func _draw_aquarium_card_effect(progress: float, kind: String, effect: Dictionary) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var scale := 0.82 + _ease_out_cubic(progress) * 0.18
	var card_size := Vector2(130, 72) * scale
	var pos := inner.position + Vector2(inner.size.x * 0.5 - card_size.x * 0.5, inner.size.y * (0.20 + sin(progress * PI) * 0.025) - card_size.y * 0.5)
	draw_circle(pos + card_size * 0.5, 78.0 + progress * 34.0, Color(0.72, 0.94, 1.0, 0.040 * fade), false, 1.4, true)
	draw_rect(Rect2(pos, card_size), Color(0.08, 0.11, 0.10, 0.74 * fade), true)
	draw_rect(Rect2(pos, card_size), Color(0.76, 0.94, 1.0, 0.42 * fade), false, 1.4, true)
	draw_rect(Rect2(pos + Vector2(12, 16), Vector2(card_size.x - 24, 28)), Color(0.40, 0.68, 0.76, 0.20 * fade), true)
	for i in range(3):
		var y := pos.y + 22 + i * 7
		_draw_wave(Vector2(pos.x + 20, y), card_size.x - 40, Color(0.88, 0.98, 1.0, 0.18 * fade), progress * 5.0 + i)
	draw_line(pos + Vector2(18, 52), pos + Vector2(card_size.x - 18, 52), Color(0.92, 0.96, 0.84, 0.32 * fade), 2.0, true)
	if kind == "create_aquarium":
		draw_line(pos + Vector2(card_size.x - 28, 18), pos + Vector2(card_size.x - 28, 38), Color(0.70, 0.94, 0.72, 0.72 * fade), 2.0, true)
		draw_line(pos + Vector2(card_size.x - 38, 28), pos + Vector2(card_size.x - 18, 28), Color(0.70, 0.94, 0.72, 0.72 * fade), 2.0, true)

func _draw_quarantine_effect(progress: float, effect: Dictionary) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var target := _active_action_point(["quarantine_animal"], Vector2(0.54, 0.48))
	var box := Rect2(target + Vector2(-44, -28 + sin(progress * PI) * 6.0), Vector2(88, 56))
	draw_rect(box, Color(0.42, 0.68, 0.86, 0.12 * fade), true)
	draw_rect(box, Color(0.70, 0.90, 1.0, 0.46 * fade), false, 1.6, true)
	for i in range(4):
		draw_line(box.position + Vector2(10 + i * 18, 6), box.position + Vector2(10 + i * 18, box.size.y - 6), Color(0.70, 0.90, 1.0, 0.16 * fade), 1.0, true)
	_draw_tool_handle(box.position + Vector2(-42, -30), box.position + Vector2(12, 8), Color(0.72, 0.80, 0.78, 0.68 * fade), 4.0)
	_draw_water_rings(target, progress, Color(0.70, 0.90, 1.0, 0.18), 3, 24.0)
	var species_id := str(effect.get("species_id", ""))
	_draw_action_animal(species_id, target + Vector2(sin(progress * TAU) * 10.0, 0), 1.0, 0.62 * fade)

func _draw_treatment_effect(progress: float, effect: Dictionary) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var center := inner.position + Vector2(inner.size.x * 0.52, inner.size.y * 0.36)
	var bottle := Rect2(center + Vector2(-22, -92 + sin(progress * PI) * 5.0), Vector2(44, 38))
	draw_rect(bottle, Color(0.40, 0.16, 0.46, 0.76 * fade), true)
	draw_rect(bottle, Color(0.92, 0.78, 1.0, 0.42 * fade), false, 1.2, true)
	draw_line(bottle.position + Vector2(8, 18), bottle.position + Vector2(36, 18), Color(0.96, 0.84, 1.0, 0.52 * fade), 1.4, true)
	for i in range(14):
		var y := bottle.end.y + fposmod(progress * 142.0 + i * 15.0, inner.size.y * 0.46)
		draw_circle(Vector2(center.x + sin(i) * 20.0, y), 2.2, Color(0.80, 0.46, 1.0, 0.46 * fade))
	_draw_speck_cloud(center + Vector2(0, 60), progress, 413, 54, Color(0.68, 0.38, 0.94, 0.24), Vector2(150, 86), Vector2(42, 16))
	for r in range(4):
		draw_arc(center + Vector2(0, 60), 32.0 + progress * 70.0 + r * 16.0, 0.0, TAU, 52, Color(0.78, 0.54, 1.0, 0.055 * fade), 1.4, true)
	var cross := center + Vector2(72, -18)
	draw_line(cross + Vector2(-11, 0), cross + Vector2(11, 0), Color(0.96, 0.78, 1.0, 0.50 * fade), 3.0, true)
	draw_line(cross + Vector2(0, -11), cross + Vector2(0, 11), Color(0.96, 0.78, 1.0, 0.50 * fade), 3.0, true)

func _draw_safeguards_effect(progress: float) -> void:
	var inner := _tank_inner()
	var fade := _effect_fade(progress)
	var settle := _ease_out_cubic(clamp(progress * 1.8, 0.0, 1.0))
	var lid_y: float = lerp(inner.position.y - 48.0, inner.position.y + 4.0, settle)
	draw_rect(Rect2(Vector2(inner.position.x + 18, lid_y), Vector2(inner.size.x - 36, 9)), Color(0.12, 0.16, 0.17, 0.82 * fade), true)
	draw_line(Vector2(inner.position.x + 26, lid_y + 2), Vector2(inner.end.x - 26, lid_y + 2), Color(0.78, 0.92, 0.94, 0.42 * fade), 1.5, true)
	var intake := Vector2(inner.end.x - 53, inner.position.y + inner.size.y * 0.43)
	var guard_radius := 7.0 + _ease_out_cubic(clamp((progress - 0.16) * 2.2, 0.0, 1.0)) * 11.0
	draw_circle(intake, guard_radius, Color(0.26, 0.39, 0.34, 0.56 * fade), true)
	for ring in range(3):
		draw_arc(intake, guard_radius + ring * 3.0, 0.0, TAU, 28, Color(0.68, 0.88, 0.76, (0.22 - ring * 0.045) * fade), 1.2, true)
	var battery := Rect2(Vector2(inner.end.x + 24, inner.end.y - 118), Vector2(48, 62))
	draw_rect(battery, Color(0.08, 0.11, 0.11, 0.88 * fade), true)
	draw_rect(battery, Color(0.72, 0.92, 0.76, 0.48 * fade), false, 1.5, true)
	draw_rect(Rect2(battery.position + Vector2(16, -7), Vector2(16, 7)), Color(0.72, 0.92, 0.76, 0.62 * fade), true)
	var charge: float = clamp((progress - 0.28) * 1.7, 0.0, 1.0)
	draw_rect(Rect2(battery.position + Vector2(8, 54 - charge * 44), Vector2(32, charge * 44)), Color(0.38, 0.82, 0.54, 0.42 * fade), true)
	var cable_start := battery.position + Vector2(0, 24)
	var cable_end := Vector2(inner.end.x - 34, inner.end.y - _substrate_height() - 20)
	_draw_tool_handle(cable_start, cable_start.lerp(cable_end, _ease_in_out_sine(clamp((progress - 0.20) * 1.55, 0.0, 1.0))), Color(0.52, 0.72, 0.66, 0.74 * fade), 3.0)
	if progress > 0.45:
		var pulse := 0.5 + sin(progress * TAU * 4.0) * 0.25
		draw_circle(battery.position + Vector2(24, 16), 4.0, Color(0.52, 1.0, 0.62, pulse * fade))
		_draw_water_rings(cable_end, progress, Color(0.62, 0.94, 0.82, 0.17), 3, 18.0)

func _draw_front_glass() -> void:
	var inner := _tank_inner()
	_draw_equipment_inside_tank(inner)
	_draw_glass_age(inner)
	draw_line(inner.position + Vector2(24, 14), inner.position + Vector2(inner.size.x * 0.46, 14), Color(1, 1, 1, 0.12), 2.0, true)
	draw_line(inner.position + Vector2(inner.size.x - 118, 30), inner.position + Vector2(inner.size.x - 34, 30), Color(1, 1, 1, 0.10), 2.0, true)
	_draw_tank_sensors()
	_draw_carry_cursor()

func _draw_glass_age(inner: Rect2) -> void:
	var maturity = state.get("maturity", {})
	var symptoms = state.get("symptoms", {})
	var glass_algae := float(maturity.get("glass_algae", 0.0))
	var biofilm := float(maturity.get("biofilm", 0.0))
	var diatom := float(symptoms.get("diatom_dust", maturity.get("diatom_film", 0.0)))
	var pathogen := float(symptoms.get("pathogen_pressure", 0.0))
	if biofilm > 0.12:
		draw_rect(inner, Color(0.85, 0.96, 0.82, biofilm * 0.025), true)
	if diatom > 0.04:
		for d in range(int(8 + diatom * 55.0)):
			var dust := Vector2(
				inner.position.x + 20.0 + fposmod(d * 71.0, inner.size.x - 40.0),
				inner.position.y + 46.0 + fposmod(d * 29.0, inner.size.y - 116.0)
			)
			draw_circle(dust, 2.0 + float(d % 4), Color(0.64, 0.43, 0.21, 0.026 + diatom * 0.055))
	if pathogen > 0.18:
		draw_rect(inner, Color(0.72, 0.78, 0.65, pathogen * 0.035), true)
	if glass_algae <= 0.04:
		return
	for i in range(int(10 + glass_algae * 70.0)):
		var pos := Vector2(
			inner.position.x + 18.0 + fposmod(i * 97.0 + sin(i) * 31.0, inner.size.x - 36.0),
			inner.position.y + 24.0 + fposmod(i * 43.0 + cos(i) * 19.0, inner.size.y - 72.0)
		)
		var radius := 3.0 + float(i % 5) * 1.4
		draw_circle(pos, radius, Color(0.36, 0.62, 0.28, 0.035 + glass_algae * 0.075))

func _draw_equipment_inside_tank(inner: Rect2) -> void:
	var equipment = state.get("equipment", {})
	var safety = state.get("safety", {})
	var filter = equipment.get("filter", {})
	var heater = equipment.get("heater", {})
	var light = equipment.get("light", {})
	var air = equipment.get("air_pump", {})
	var flow := float(filter.get("effective_flow", filter.get("flow", 0.0)))
	var bypass := float(filter.get("bypass_risk", 0.0))
	var filter_color := Color(0.04, 0.07, 0.075, 0.72)
	if str(filter.get("failure_mode", "")) != "":
		filter_color = Color(0.18, 0.10, 0.07, 0.82)
	elif bypass > 0.35:
		filter_color = Color(0.13, 0.115, 0.065, 0.78)
	draw_rect(Rect2(Vector2(inner.end.x - 46, inner.position.y + 56), Vector2(16, inner.size.y - _substrate_height() - 104)), filter_color, true)
	draw_rect(Rect2(Vector2(inner.end.x - 58, inner.position.y + 62), Vector2(10, 74)), filter_color.lightened(0.12), true)
	if bool(safety.get("intake_guard", false)):
		var intake_guard := Vector2(inner.end.x - 53, inner.position.y + 99)
		draw_circle(intake_guard, 12.0, Color(0.23, 0.34, 0.30, 0.76))
		draw_arc(intake_guard, 14.0, 0.0, TAU, 24, Color(0.62, 0.82, 0.70, 0.38), 1.2, true)
	for i in range(5):
		draw_circle(Vector2(inner.end.x - 66 - flow * 34.0 + sin(Time.get_ticks_msec() / 450.0 + i) * (4.0 + bypass * 5.0), inner.position.y + 88 + i * 38), 1.8 + bypass * 0.8, Color(0.78, 0.94, 0.98, 0.18 + flow * 0.16))
	if bool(heater.get("enabled", true)):
		var hx := inner.position.x + 42
		var hy := inner.position.y + 96
		draw_rect(Rect2(Vector2(hx, hy), Vector2(10, inner.size.y - _substrate_height() - 144)), Color(0.09, 0.10, 0.10, 0.70), true)
		var heat_alpha := 0.18 + float(heater.get("thermostat_stickiness", 0.0)) * 0.18
		if str(heater.get("failure_mode", "")) != "":
			heat_alpha = 0.42
		draw_line(Vector2(hx + 5, hy + 12), Vector2(hx + 5, inner.end.y - _substrate_height() - 44), Color(1.0, 0.44, 0.30, heat_alpha), 3.0, true)
	if bool(air.get("enabled", true)) and float(air.get("output", 0.0)) > 0.01:
		var output := float(air.get("effective_output", float(air.get("output", 0.5)) * float(air.get("health", 1.0))))
		var stone := Vector2(inner.position.x + inner.size.x * 0.18, inner.end.y - _substrate_height() - 16)
		draw_rect(Rect2(stone - Vector2(18, 4), Vector2(36, 8)), Color(0.18, 0.20, 0.19, 0.64), true)
		for i in range(12):
			var rise := fposmod(Time.get_ticks_msec() / 900.0 + float(i) * 0.11, 1.0)
			var pos := stone + Vector2(sin(i * 1.7) * 15.0, -rise * inner.size.y * 0.68)
			draw_circle(pos, 1.3 + float(i % 3) * 0.4, Color(0.85, 0.97, 1.0, 0.12 + output * 0.26))
	if bool(safety.get("lid_fitted", false)):
		draw_rect(Rect2(inner.position + Vector2(18, 3), Vector2(inner.size.x - 36, 7)), Color(0.10, 0.14, 0.15, 0.72), true)
		draw_line(inner.position + Vector2(30, 5), Vector2(inner.end.x - 30, inner.position.y + 5), Color(0.78, 0.92, 0.94, 0.22), 1.0, true)
	var clock = state.get("clock", {})
	if bool(light.get("enabled", true)) and bool(clock.get("lights_on", true)) and float(light.get("hours_per_day", 0.0)) > 0.0:
		var spectrum := float(light.get("effective_spectrum", light.get("plant_spectrum", 0.82)))
		var par := float(light.get("par_output", light.get("health", 1.0)))
		var alpha: float = clamp(0.04 + spectrum * par * 0.12, 0.035, 0.18)
		draw_rect(Rect2(inner.position.x + 32, inner.position.y + 8, inner.size.x - 64, 10), Color(0.88, 0.96, 1.0, alpha), true)

func _draw_tank_sensors() -> void:
	if state.is_empty():
		return
	var inner := _tank_inner()
	var water = state.get("water", {})
	var stability = state.get("stability", {})
	var biology = state.get("biology", {})
	var residue = state.get("action_residue", {})
	var font := get_theme_default_font()
	var small := 12
	var normal := 15
	var board := Rect2(inner.position + Vector2(18, 18), Vector2(214, 246))
	draw_rect(board, Color(0.03, 0.045, 0.045, 0.72), true)
	draw_rect(board, Color(0.74, 0.92, 0.89, 0.24), false, 1.4, true)
	draw_string(font, board.position + Vector2(12, 22), "WATER PROBE", HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color("#c9e7df"))
	_draw_sensor_line(board.position + Vector2(12, 46), "pH", "%.2f" % float(water.get("ph", 0.0)), _range_color(float(water.get("ph", 0.0)), 6.5, 8.2, 5.8, 8.6), normal)
	_draw_sensor_line(board.position + Vector2(12, 72), "O2", "%.1f mg/L" % float(water.get("oxygen_mg_l", 0.0)), _range_color(float(water.get("oxygen_mg_l", 0.0)), 6.0, 9.0, 4.8, 10.0), normal)
	_draw_sensor_line(board.position + Vector2(12, 98), "TAN", "%.3f" % float(water.get("ammonia_mg_l", 0.0)), _max_color(float(water.get("ammonia_mg_l", 0.0)), 0.02, 0.15), normal)
	_draw_sensor_line(board.position + Vector2(12, 124), "NH3", "%.4f" % float(water.get("free_ammonia_mg_l", 0.0)), _max_color(float(water.get("free_ammonia_mg_l", 0.0)), 0.015, 0.03), normal)
	_draw_sensor_line(board.position + Vector2(12, 150), "NO2", "%.3f" % float(water.get("nitrite_mg_l", 0.0)), _max_color(float(water.get("nitrite_mg_l", 0.0)), 0.05, 0.3), normal)
	_draw_sensor_line(board.position + Vector2(12, 176), "ORP", "%.0f mV" % float(water.get("redox_mv", 0.0)), _range_color(float(water.get("redox_mv", 0.0)), 280.0, 430.0, 220.0, 460.0), normal)
	_draw_sensor_line(board.position + Vector2(12, 202), "STB", "%.0f%%" % (float(stability.get("stability_score", 1.0)) * 100.0), _range_color(float(stability.get("stability_score", 1.0)), 0.72, 1.0, 0.45, 1.0), normal)
	_draw_sensor_line(board.position + Vector2(12, 228), "DOC", "%.2f" % float(water.get("dissolved_organics", 0.0)), _max_color(float(water.get("dissolved_organics", 0.0)), 0.45, 0.9), normal)

	var strip := Rect2(Vector2(inner.end.x - 70, inner.position.y + 86), Vector2(34, inner.size.y - SAND_HEIGHT - 132))
	draw_rect(strip, Color(0.92, 0.88, 0.72, 0.24), true)
	draw_rect(strip, Color(0.96, 0.98, 0.92, 0.46), false, 1.2, true)
	var temp := float(water.get("temperature_c", 0.0))
	for i in range(7):
		var y := strip.position.y + 18 + i * ((strip.size.y - 38) / 6.0)
		draw_line(Vector2(strip.position.x + 8, y), Vector2(strip.position.x + 22, y), Color(0.9, 0.94, 0.88, 0.55), 1.0, true)
	var temp_y := remap(clamp(temp, 18.0, 30.0), 18.0, 30.0, strip.end.y - 22, strip.position.y + 18)
	draw_circle(Vector2(strip.position.x + 17, temp_y), 7.0, _range_color(temp, 23.0, 26.5, 20.0, 29.0))
	draw_string(font, strip.position + Vector2(-10, -10), "%.1f C" % temp, HORIZONTAL_ALIGNMENT_CENTER, 56, small, Color("#edf7ed"))

	var card := Rect2(Vector2(inner.end.x - 238, inner.position.y + 24), Vector2(144, 88))
	draw_rect(card, Color("#d8c697", 0.82), true)
	draw_rect(card, Color("#604a30", 0.74), false, 1.2, true)
	draw_string(font, card.position + Vector2(10, 20), "TEST STRIP", HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color("#2f271c"))
	_draw_test_pad(card.position + Vector2(12, 34), "NO3", "%.0f" % float(water.get("nitrate_mg_l", 0.0)), _max_color(float(water.get("nitrate_mg_l", 0.0)), 25.0, 45.0))
	_draw_test_pad(card.position + Vector2(12, 58), "PO4", "%.2f" % float(water.get("phosphate_mg_l", 0.0)), _max_color(float(water.get("phosphate_mg_l", 0.0)), 0.15, 0.5))
	var filter = state.get("equipment", {}).get("filter", {})
	var cycle = state.get("cycle", {})
	var filter_text := "filter %.0f%%" % (float(filter.get("effective_flow", filter.get("flow", 0.0))) * 100.0)
	var cycle_text := "cycle %s" % ("ready" if bool(cycle.get("ready_for_animals", false)) else "new")
	var graze_text := "grazing %.0f%%" % (float(biology.get("grazing_pressure", 0.0)) * 100.0)
	var residue_text := "care haze %.0f%%" % ((float(residue.get("suspended_debris", 0.0)) + float(residue.get("filter_biofilm_shed", 0.0))) * 100.0)
	draw_string(font, inner.position + Vector2(24, inner.end.y - SAND_HEIGHT - 14), "%s  /  %s  /  %s  /  %s" % [filter_text, cycle_text, graze_text, residue_text], HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color(0.85, 0.98, 0.92, 0.72))

func _draw_sensor_line(pos: Vector2, label: String, value: String, color: Color, size_px: int) -> void:
	var font := get_theme_default_font()
	draw_circle(pos + Vector2(5, -4), 4.0, color)
	draw_string(font, pos + Vector2(18, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color("#a8cfc8"))
	draw_string(font, pos + Vector2(72, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color("#edf7ef"))

func _draw_test_pad(pos: Vector2, label: String, value: String, color: Color) -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(pos, Vector2(18, 14)), color, true)
	draw_rect(Rect2(pos, Vector2(18, 14)), Color("#3b2e1e", 0.4), false, 1.0, true)
	draw_string(font, pos + Vector2(26, 12), "%s %s" % [label, value], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#2f271c"))

func _range_color(value: float, good_min: float, good_max: float, warn_min: float, warn_max: float) -> Color:
	if value >= good_min and value <= good_max:
		return Color("#66d99a")
	if value >= warn_min and value <= warn_max:
		return Color("#e9c85f")
	return Color("#ff766a")

func _max_color(value: float, good_max: float, warn_max: float) -> Color:
	if value <= good_max:
		return Color("#66d99a")
	if value <= warn_max:
		return Color("#e9c85f")
	return Color("#ff766a")

func _draw_carry_cursor() -> void:
	var mouse := get_viewport().get_mouse_position()
	var inner := _tank_inner()
	if not inner.has_point(mouse):
		return
	if not selected_animal_tool.is_empty():
		var spec: Dictionary = species.get(str(selected_animal_tool.get("species_id", "")), {})
		var name := str(spec.get("common_name", "animal"))
		draw_arc(mouse + Vector2(0, 6), 34.0, PI * 0.08, PI * 0.92, 28, Color(0.86, 0.94, 0.96, 0.72), 2.0, true)
		draw_line(mouse + Vector2(24, 30), mouse + Vector2(54, 66), Color(0.72, 0.80, 0.82, 0.58), 2.0, true)
		draw_circle(mouse + Vector2(-7, 5), 6.0, Color(str(spec.get("color", "#8fd1d0"))).lerp(Color.WHITE, 0.25))
		draw_string(get_theme_default_font(), mouse + Vector2(18, -14), "Net: %s" % name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#eef8f4"))
		return
	if not selected_scape_tool.is_empty():
		var category := str(selected_scape_tool.get("category", ""))
		var item_type := str(selected_scape_tool.get("type", ""))
		var normalized := Vector2(
			clamp((mouse.x - inner.position.x) / inner.size.x, 0.0, 1.0),
			clamp((mouse.y - inner.position.y) / inner.size.y, 0.0, 1.0)
		)
		var valid := _client_position_valid(category, item_type, normalized, true)
		var color := Color(0.74, 0.92, 0.82, 0.54) if valid else Color(1.0, 0.42, 0.36, 0.50)
		draw_circle(mouse, 28.0, color, false, 2.0, true)
		if scape_textures.has(item_type):
			var texture: Texture2D = scape_textures[item_type]
			draw_texture_rect(texture, Rect2(mouse - Vector2(26, 26), Vector2(52, 52)), false, Color(1, 1, 1, 0.82))
		else:
			draw_circle(mouse, 16.0, color)

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
		_draw_animal_shadow(str(animal.get("species_id", "")), pos, visual)
		_draw_animal_wake(pos, facing, visual, animal)
		if _draw_fish_sprite(str(animal.get("species_id", "")), pos, facing, stress, health, visual):
			_draw_health_marks(animal, pos, facing)
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
		_draw_health_marks(animal, pos, facing)

func _draw_animal_shadow(species_id: String, pos: Vector2, visual: Dictionary) -> void:
	var draw_size := _fish_sprite_size(species_id)
	var speed: float = clamp(float(visual.get("speed_ratio", 0.0)), 0.0, 1.8)
	var bank: float = abs(float(visual.get("bank", 0.0)))
	var offset := Vector2(5.0, 10.0 + speed * 4.0 + bank * 18.0)
	_draw_ellipse(pos + offset, draw_size.x * (0.22 + speed * 0.025), draw_size.y * 0.11, Color(0.01, 0.025, 0.028, 0.065 + speed * 0.018), true)

func _draw_animal_wake(pos: Vector2, facing: float, visual: Dictionary, animal: Dictionary) -> void:
	var speed: float = clamp(float(visual.get("speed_ratio", 0.0)), 0.0, 1.8)
	var stress: float = clamp(float(animal.get("acute_stress", 0.0)), 0.0, 1.0)
	if speed < 0.10 and stress < 0.35:
		return
	var phase := float(visual.get("phase", 0.0))
	var bank: float = float(visual.get("bank", 0.0))
	var alpha: float = clamp(speed * 0.10 + stress * 0.08, 0.02, 0.18)
	for i in range(3):
		var back := pos + Vector2((-20.0 - i * 12.0) * facing, sin(phase * 2.0 + i) * 4.0 + bank * 16.0)
		var tail := back + Vector2((-22.0 - speed * 16.0) * facing, sin(phase * 1.4 + i * 0.8) * (4.0 + speed * 3.0) + bank * 10.0)
		draw_line(back, tail, Color(0.80, 0.96, 1.0, alpha * (1.0 - float(i) * 0.22)), 1.1, true)

func _draw_fish_sprite(species_id: String, pos: Vector2, facing: float, stress: float, health: float, visual: Dictionary) -> bool:
	if not fish_textures.has(species_id):
		return false
	var texture: Texture2D = fish_textures[species_id]
	var draw_size := _fish_sprite_size(species_id)
	var warmth: float = clamp(stress * 0.18 + (1.0 - health) * 0.22, 0.0, 0.35)
	var modulate := Color(1.0, 1.0 - warmth * 0.18, 1.0 - warmth * 0.28, 1.0)
	var phase := float(visual.get("phase", 0.0))
	var speed: float = clamp(float(visual.get("speed_ratio", 0.0)), 0.0, 1.8)
	var bank: float = clamp(float(visual.get("bank", 0.0)), -0.28, 0.28)
	var turn_energy: float = clamp(float(visual.get("turn_energy", 0.0)), 0.0, 1.0)
	var bob: float = sin(phase * 2.1) * lerp(0.45, 2.25, speed)
	var rotation: float = bank + sin(phase * 1.7) * lerp(0.006, 0.030, speed) * facing
	var squeeze: float = 1.0 + sin(phase * (2.9 + speed * 0.8)) * (0.010 + speed * 0.018 + turn_energy * 0.010)
	var fin_lift: float = 1.0 + cos(phase * 2.4) * (0.008 + speed * 0.016)
	draw_set_transform(pos + Vector2(0, bob), rotation, Vector2((1.0 if facing >= 0 else -1.0) * squeeze, fin_lift / max(0.85, squeeze)))
	draw_texture_rect(texture, Rect2(-draw_size * 0.5, draw_size), false, modulate)
	var clock: Dictionary = state.get("clock", {})
	if bool(clock.get("lights_on", true)):
		var glint_alpha: float = 0.05 + speed * 0.025 + turn_energy * 0.015
		draw_line(Vector2(-draw_size.x * 0.17, -draw_size.y * 0.16), Vector2(draw_size.x * 0.22, -draw_size.y * 0.24), Color(0.88, 1.0, 0.92, glint_alpha), 1.0, true)
		draw_circle(Vector2(draw_size.x * 0.12, -draw_size.y * 0.20), 1.1, Color(0.94, 1.0, 0.96, glint_alpha * 1.25))
	if speed > 0.20:
		var tail_x := -draw_size.x * 0.48
		for i in range(2):
			var wave := sin(phase * (3.4 + speed) + i) * 5.0 * speed
			draw_line(Vector2(tail_x, -4.0 + i * 8.0), Vector2(tail_x - 10.0, -6.0 + i * 12.0 + wave), Color(0.88, 0.96, 1.0, 0.12 * speed), 1.2, true)
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

func _draw_health_marks(animal: Dictionary, pos: Vector2, facing: float) -> void:
	_draw_behavior_marks(animal, pos, facing)
	if bool(animal.get("quarantined", false)):
		draw_arc(pos + Vector2(0, 2), 28.0, 0.05, TAU - 0.05, 36, Color(0.70, 0.88, 1.0, 0.22), 1.4, true)
	var disease := str(animal.get("disease", ""))
	if disease == "":
		return
	var stage := str(animal.get("disease_stage", "early"))
	var alpha := 0.34 if stage == "early" else 0.48 if stage == "visible" else 0.66
	if disease.contains("spot") or disease.contains("ich") or disease.contains("parasite"):
		for i in range(5 if stage != "severe" else 8):
			var offset := Vector2(-14.0 + float(i % 4) * 8.0, -5.0 + float(i / 4) * 8.0)
			draw_circle(pos + Vector2(offset.x * facing, offset.y), 1.35, Color(0.95, 0.97, 0.88, alpha))
	if disease.contains("fin rot") or float(animal.get("fin_condition", 1.0)) < 0.55:
		draw_line(pos + Vector2(-24.0 * facing, -4.0), pos + Vector2(-34.0 * facing, -10.0), Color(0.92, 0.78, 0.68, alpha), 1.5, true)
		draw_line(pos + Vector2(-24.0 * facing, 4.0), pos + Vector2(-35.0 * facing, 10.0), Color(0.92, 0.78, 0.68, alpha), 1.5, true)
	if disease.contains("gill"):
		draw_arc(pos + Vector2(11.0 * facing, 0), 7.0, -PI * 0.35, PI * 0.35, 8, Color(1.0, 0.45, 0.40, alpha), 1.6, true)

func _draw_behavior_marks(animal: Dictionary, pos: Vector2, facing: float) -> void:
	var routine: String = str(animal.get("routine", ""))
	var fear: float = clamp(float(animal.get("fear_memory", 0.0)), 0.0, 1.0)
	var cohesion: float = clamp(float(animal.get("school_cohesion", 0.0)), 0.0, 1.0)
	var territory: float = clamp(float(animal.get("territory_pressure", 0.0)), 0.0, 1.0)
	var confidence: float = clamp(float(animal.get("confidence", 0.5)), 0.0, 1.0)
	var intent := str(animal.get("behavior_intent", ""))
	if routine == "school" and cohesion > 0.42:
		draw_arc(pos + Vector2(0, 2), 24.0, PI * 0.08, PI * 0.92, 18, Color(0.68, 0.92, 1.0, 0.08 + cohesion * 0.12), 1.1, true)
	if routine == "school" and intent == "regrouping":
		var pulse: float = 0.5 + sin(Time.get_ticks_msec() / 180.0 + float(animal.get("position_seed", 0))) * 0.22
		draw_arc(pos, 31.0 + pulse * 6.0, PI * 1.08, PI * 1.82, 14, Color(0.72, 0.94, 1.0, 0.22), 1.3, true)
	if routine == "school" and intent == "scouting":
		draw_line(pos + Vector2(20.0 * facing, -14.0), pos + Vector2(34.0 * facing, -14.0), Color(0.92, 0.82, 0.48, 0.20), 1.2, true)
		draw_line(pos + Vector2(34.0 * facing, -14.0), pos + Vector2(28.0 * facing, -18.0), Color(0.92, 0.82, 0.48, 0.20), 1.2, true)
	if intent == "grazing" or intent == "sifting substrate":
		for i in range(3):
			var speck := pos + Vector2((-18.0 + i * 10.0) * facing, 18.0 + sin(Time.get_ticks_msec() / 220.0 + i) * 3.0)
			draw_circle(speck, 1.4, Color(0.70, 0.56, 0.30, 0.14))
	if intent == "current riding":
		draw_arc(pos + Vector2(-16.0 * facing, 2.0), 20.0, -0.55, 0.55, 10, Color(0.72, 0.94, 1.0, 0.14), 1.0, true)
	if intent == "conserving energy":
		draw_circle(pos + Vector2(-8.0 * facing, 2.0), 19.0, Color(0.28, 0.40, 0.46, 0.08))
	if routine == "hide" or fear > 0.58 or confidence < 0.24:
		var alpha: float = 0.08 + max(fear, 1.0 - confidence) * 0.16
		draw_circle(pos + Vector2(-8.0 * facing, 2.0), 18.0, Color(0.10, 0.16, 0.14, alpha))
	if territory > 0.52 and routine in ["display", "patrol"]:
		draw_arc(pos, 31.0, 0.1, TAU - 0.1, 36, Color(1.0, 0.78, 0.34, 0.10 + territory * 0.14), 1.8, true)
		draw_line(pos + Vector2(-20.0 * facing, -16.0), pos + Vector2(18.0 * facing, -16.0), Color(1.0, 0.72, 0.30, 0.10 + territory * 0.18), 1.2, true)
	if routine == "rest":
		var rest: float = clamp(float(animal.get("rest_quality", 0.75)), 0.0, 1.0)
		draw_arc(pos + Vector2(-7.0 * facing, -12.0), 12.0, PI * 1.02, PI * 1.78, 10, Color(0.78, 0.88, 1.0, 0.08 + rest * 0.14), 1.3, true)

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
	var welfare = state.get("welfare", {})
	var status = str(summary.get("status", "stable")).capitalize()
	var living := int(summary.get("living_animals", 0))
	var stressed := int(summary.get("stressed_animals", 0))
	status_label.text = "%s - %d animals - %d stressed - welfare %d" % [status, living, stressed, int(summary.get("welfare_score", welfare.get("score", 100)))]
	var issues: Array = welfare.get("issues", [])
	if issues.size() > 0:
		var first_issue: Dictionary = issues[0]
		summary_label.text = "%s: %s" % [first_issue.get("title", "Welfare issue"), first_issue.get("details", "Check stocking, grouping, cover, and water quality.")]
	else:
		summary_label.text = "The aquarium keeps living in the background. Add animals deliberately, acclimate them, and watch water plus welfare signals."
	var aquarium = state.get("aquarium", {})
	if scape_label:
		var biology = state.get("biology", {})
		var scape_data: Dictionary = aquarium.get("scape", {})
		var custom_count: int = scape_data.get("objects", []).size()
		scape_label.text = "%d custom pieces. Plants and cleanup crews affect nitrate, oxygen, algae, cover, waste, and maintenance. Cover %.0f%% - algae control %.0f%% - grazing %.0f%% - upkeep %.0f%%" % [
			custom_count,
			float(aquarium.get("plant_cover", 0.0)) * 100.0,
			float(aquarium.get("algae_control", 0.0)) * 100.0,
			float(biology.get("grazing_pressure", 0.0)) * 100.0,
			float(aquarium.get("maintenance_load", 0.0)) * 100.0
		]
	_sync_food_controls()
	_sync_equipment_controls()
	animal_list.clear()
	animal_ids.clear()
	for animal in state.get("animals", []):
		var alive: bool = bool(animal.get("alive", true))
		var line := "%s - %s - stress %.0f%% - health %.0f%% - hunger %.0f%%" % [
			animal.get("name", "animal"),
			animal.get("behavior", "observing"),
			float(animal.get("acute_stress", 0.0)) * 100.0,
			float(animal.get("health", 1.0)) * 100.0,
			float(animal.get("hunger", 0.0)) * 100.0
		]
		if float(animal.get("injury", 0.0)) > 0.05:
			line += " - injury %.0f%%" % (float(animal.get("injury", 0.0)) * 100.0)
		if float(animal.get("body_condition", 1.0)) < 0.62:
			line += " - thin %.0f%%" % (float(animal.get("body_condition", 1.0)) * 100.0)
		if float(animal.get("gill_condition", 1.0)) < 0.68:
			line += " - gills %.0f%%" % (float(animal.get("gill_condition", 1.0)) * 100.0)
		if float(animal.get("fin_condition", 1.0)) < 0.68:
			line += " - fins %.0f%%" % (float(animal.get("fin_condition", 1.0)) * 100.0)
		if float(animal.get("parasite_load", 0.0)) > 0.25:
			line += " - parasite %.0f%%" % (float(animal.get("parasite_load", 0.0)) * 100.0)
		if bool(animal.get("quarantined", false)):
			line += " - quarantine %.0f d" % float(animal.get("quarantine_days_remaining", 0.0))
		if float(animal.get("breeding_condition", 0.0)) > 0.6:
			line += " - breeding"
		var welfare_reasons: Array = animal.get("welfare_reasons", [])
		if welfare_reasons.size() > 0 and alive:
			line += " - %s" % welfare_reasons[0]
		if str(animal.get("disease", "")) != "" and alive:
			line += " - %s (%s)" % [animal.get("disease", ""), animal.get("disease_stage", "early")]
			var visible_symptoms: Array = animal.get("visible_symptoms", [])
			if visible_symptoms.size() > 0:
				line += " - %s" % ", ".join(visible_symptoms.slice(0, 2))
		if not alive:
			line = "%s - died: %s" % [animal.get("name", "animal"), animal.get("cause_of_death", "unknown")]
		animal_list.add_item(line)
		animal_ids.append(str(animal.get("id", "")))

func _format_water(key: String, value: float) -> String:
	match key:
		"temperature_c":
			return "Temperature: %.1f C" % value
		"ph":
			return "pH: %.2f" % value
		"oxygen_mg_l":
			return "Oxygen: %.1f mg/L" % value
		"co2_mg_l":
			return "CO2: %.1f mg/L" % value
		"ammonia_mg_l":
			return "Ammonia: %.3f mg/L" % value
		"nitrite_mg_l":
			return "Nitrite: %.3f mg/L" % value
		"nitrate_mg_l":
			return "Nitrate: %.1f mg/L" % value
		"phosphate_mg_l":
			return "Phosphate: %.2f mg/L" % value
		"kh_dkh":
			return "KH / alkalinity: %.1f dKH" % value
		"alkalinity_dkh":
			return "Alkalinity: %.1f dKH" % value
		"calcium_mg_l":
			return "Calcium: %.0f mg/L" % value
		"magnesium_mg_l":
			return "Magnesium: %.0f mg/L" % value
		"trace_elements":
			return "Trace reserves: %.0f%%" % (value * 100.0)
		"silicate_mg_l":
			return "Silicate: %.2f mg/L" % value
		"tds_mg_l":
			return "TDS: %.0f mg/L" % value
		"salinity_ppt":
			return "Salinity: %.1f ppt" % value
		"water_level":
			return "Water level: %.0f%%" % (value * 100.0)
		"chlorine_mg_l":
			return "Chlorine: %.3f mg/L" % value
		"chloramine_mg_l":
			return "Chloramine: %.3f mg/L" % value
		"surface_film":
			return "Surface film: %.0f%%" % (value * 100.0)
		"detritus":
			return "Detritus: %.0f%%" % (value * 100.0)
		"parasite_pressure":
			return "Parasite pressure: %.0f%%" % (value * 100.0)
		"bacterial_pressure":
			return "Bacterial pressure: %.0f%%" % (value * 100.0)
	return "%s: %.2f" % [key, value]
