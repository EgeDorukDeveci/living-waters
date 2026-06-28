from __future__ import annotations

import json
import math
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "background"))

from simulation import AquariumSimulation, clear_state, default_state, load_species  # noqa: E402


def assert_between(value: float, low: float, high: float, label: str) -> None:
    assert low <= value <= high, f"{label}: expected {low}..{high}, got {value}"


def animal(species: dict, species_id: str, name: str, seed: int = 1) -> dict:
    from simulation import make_animal

    return make_animal(species[species_id], name, seed)


def test_nitrogen_cycle_and_water_change() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    state["water"]["ammonia_mg_l"] = 0.7
    sim.advance(24 * 3600)
    assert state["water"]["ammonia_mg_l"] < 0.7
    assert state["water"]["nitrite_mg_l"] > 0.0 or state["water"]["nitrate_mg_l"] > 0.0
    before = state["water"]["nitrate_mg_l"]
    state["source_water"]["nitrate_mg_l"] = 0.0
    state["source_water"]["phosphate_mg_l"] = 0.0
    sim.water_change(0.5)
    assert state["water"]["nitrate_mg_l"] < before * 0.65


def test_water_change_shock_depends_on_replacement_water() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    fish = animal(species, "neon_tetra", "Shock", 1)
    state["animals"].append(fish)
    state["maturity"]["mulm"] = 0.7
    sim = AquariumSimulation(species, state)
    before = fish["acute_stress"]
    sim.water_change(
        0.55,
        conditioner_used=False,
        replacement_temp_c=12.0,
        replacement_ph=8.8,
        replacement_gh_dgh=24.0,
        disturbed_substrate=True,
    )
    assert state["maturity"]["last_water_change_shock"] > 0.5
    assert fish["acute_stress"] > before
    assert state["water"]["chlorine_mg_l"] > 0
    assert state["water"]["turbidity"] > 0.02
    assert state["maturity"]["mulm"] < 0.7


def test_phosphate_can_be_reduced_by_water_change_and_media() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    state["water"]["phosphate_mg_l"] = 1.2
    state["water"]["organic_waste"] = 0.0
    state["food"]["decaying"] = 0.0
    sim.water_change(0.5)
    assert state["water"]["phosphate_mg_l"] < 0.7
    state["water"]["phosphate_mg_l"] = 1.0
    state["equipment"]["filter"]["media"]["chemical"]["phosphate_remover_remaining"] = 1.0
    sim.advance(24 * 3600)
    assert state["water"]["phosphate_mg_l"] < 0.97
    assert state["equipment"]["filter"]["media"]["chemical"]["phosphate_remover_remaining"] < 1.0


def test_plants_and_macroalgae_use_some_phosphate() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = clear_state(species, "Planted Test", "freshwater", 90)
    state["aquarium"]["scape"]["plants"] = [{"type": "hornwort", "quantity": 18, "health": 1.0}]
    state["water"]["phosphate_mg_l"] = 0.7
    state["water"]["nitrate_mg_l"] = 20.0
    state["water"]["organic_waste"] = 0.0
    state["food"]["decaying"] = 0.0
    state["equipment"]["filter"]["media"]["chemical"]["phosphate_remover_remaining"] = 0.0
    sim = AquariumSimulation(species, state)
    before = state["water"]["phosphate_mg_l"]
    sim.advance(12 * 3600)
    assert state["water"]["phosphate_mg_l"] < before


def test_leftover_food_mineralizes_slowly() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = clear_state(species, "Slow Food Test", "freshwater", 80)
    sim = AquariumSimulation(species, state)
    sim.feed(0.6)
    sim.advance(6 * 3600)
    assert state["water"]["ammonia_mg_l"] < 0.04
    assert state["food"]["available"] < 0.6
    assert state["food"]["decaying"] > 0.0
    sim.advance(42 * 3600)
    assert state["water"]["ammonia_mg_l"] < 0.18


def test_day_night_clock_fields_are_published() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    sim.advance(5)
    assert_between(float(state["clock"]["local_hour"]), 0.0, 24.0, "local hour")
    assert state["clock"]["day_phase"] in {"dawn", "day", "dusk", "night"}
    assert isinstance(state["clock"]["lights_on"], bool)


def test_source_water_and_conditioner_affect_water_changes() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = clear_state(species, "Tap Test", "freshwater", 90)
    state["source_water"]["nitrate_mg_l"] = 12.0
    state["source_water"]["phosphate_mg_l"] = 0.4
    state["source_water"]["chlorine_mg_l"] = 0.3
    state["source_water"]["chloramine_mg_l"] = 0.12
    sim = AquariumSimulation(species, state)
    sim.water_change(0.5, conditioner_used=False)
    assert state["water"]["nitrate_mg_l"] > 5.0
    assert state["water"]["phosphate_mg_l"] > 0.15
    assert state["water"]["chlorine_mg_l"] > 0.1
    assert state["water"]["chloramine_mg_l"] > 0.04
    before_bacteria = state["biology"]["ammonia_bacteria"]
    sim.advance(2 * 3600)
    assert state["biology"]["ammonia_bacteria"] < before_bacteria


def test_small_maintenance_actions_reduce_visible_pressure() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    state["food"]["available"] = 0.8
    state["food"]["decaying"] = 0.5
    state["biology"]["algae"] = 0.7
    state["maturity"]["glass_algae"] = 0.8
    state["aquarium"]["scape"]["plants"] = [{"type": "hornwort", "quantity": 30, "health": 0.65}]
    sim.remove_uneaten_food()
    assert state["food"]["available"] < 0.3
    sim.scrape_algae()
    assert state["maturity"]["glass_algae"] < 0.25
    sim.trim_plants()
    assert state["aquarium"]["scape"]["plants"][0]["quantity"] < 30


def test_overcleaned_filter_disturbs_biofilter() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    before = state["biology"]["ammonia_bacteria"]
    sim.service_filter(overclean=True)
    assert state["biology"]["ammonia_bacteria"] < before * 0.7
    assert state["maintenance"]["last_filter_overcleaned"] is True
    assert any("over-cleaned" in event["title"] for event in state["events"])


def test_symptoms_publish_visible_tank_state() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    state["water"]["turbidity"] = 0.6
    state["water"]["surface_film"] = 0.7
    state["water"]["detritus"] = 0.7
    state["biology"]["algae"] = 0.75
    sim.advance(5)
    assert state["symptoms"]["cloudiness"] > 0.5
    assert state["symptoms"]["surface_film"] > 0.5
    assert state["symptoms"]["dirty_substrate"] > 0.5
    assert state["symptoms"]["green_water"] > 0.5


def test_tank_maturity_changes_with_time_and_neglect() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = clear_state(species, "Old Desk Tank", "freshwater", 60)
    sim = AquariumSimulation(species, state)
    state["cycle"]["days_running"] = 320
    state["maintenance"]["last_water_change"] = "2019-01-01T00:00:00"
    state["water"]["nitrate_mg_l"] = 80
    state["water"]["kh_dkh"] = 0.5
    before = state["maturity"]["biofilm"]
    sim.advance(24 * 3600)
    assert state["maturity"]["biofilm"] > before
    assert state["maturity"]["old_tank_risk"] > 0.5
    assert any(event.get("title") == "Old-tank pressure is building" for event in state["events"])


def test_fish_routine_reflects_surface_stress() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    fish = animal(species, "neon_tetra", "Breathing Hard", 1)
    state["animals"].append(fish)
    state["water"]["oxygen_mg_l"] = 2.0
    state["equipment"]["air_pump"]["enabled"] = False
    state["equipment"]["filter"]["enabled"] = False
    sim = AquariumSimulation(species, state)
    sim.advance(3600)
    assert fish["routine"] == "surface"
    assert "surface" in fish["behavior"]


def test_default_tank_starts_empty() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    assert state["animals"] == []
    assert state["summary"].get("living_animals", 0) == 0
    sim.switch_system("saltwater")
    assert state["animals"] == []


def test_clear_tank_setup_is_empty_uncycled_and_sized() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = clear_state(species, "Desk Tank", "freshwater", 40)
    sim = AquariumSimulation(species, state)
    assert state["aquarium"]["name"] == "Desk Tank"
    assert state["aquarium"]["gross_litres"] == 40
    assert state["aquarium"]["effective_litres"] < 40
    assert state["aquarium"]["scape"]["objects"] == []
    assert state["aquarium"]["scape"]["plants"] == []
    assert state["cycle"]["ready_for_animals"] is False
    assert state["biology"]["ammonia_bacteria"] < 0.1
    sim.setup_clear_aquarium("Reef Test", "saltwater", 120)
    assert state["aquarium"]["gross_litres"] == 120
    assert state["water"]["system"] == "saltwater"
    assert state["water"]["salinity_ppt"] >= 34


def test_legacy_preplaced_animals_are_cleared() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    state["animals"] = []
    for index in range(8):
        state["animals"].append(animal(species, "neon_tetra", f"Neon {index + 1}", index))
    for index in range(6):
        state["animals"].append(animal(species, "peppered_cory", f"Cory {index + 1}", 20 + index))
    for index in range(10):
        state["animals"].append(animal(species, "cherry_shrimp", f"Shrimp {index + 1}", 40 + index))
    AquariumSimulation(species, state)
    assert state["animals"] == []
    assert state["events"][0]["title"] == "Starter animals removed"


def test_schooling_and_tank_size_stress() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    state["animals"].append(animal(species, "neon_tetra", "Lonely Neon", 1))
    sim = AquariumSimulation(species, state)
    sim.advance(4 * 3600)
    neon = next(a for a in state["animals"] if a["species_id"] == "neon_tetra")
    assert neon["social_satisfaction"] < 0.3
    assert neon["acute_stress"] > 0.1


def test_lone_schooling_fish_declines_from_social_deprivation() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    state["animals"].append(animal(species, "neon_tetra", "Lonely Neon", 1))
    sim = AquariumSimulation(species, state)
    start_health = state["animals"][0]["health"]
    sim.advance(24 * 3600)
    neon = state["animals"][0]
    assert state["welfare"]["status"] == "critical"
    assert any("needs a group" in issue["title"] for issue in state["welfare"]["issues"])
    assert "undersized" in neon["welfare_reasons"][0]
    assert neon["health"] < start_health - 0.2


def test_proper_neon_school_avoids_social_crisis() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    for index in range(6):
        state["animals"].append(animal(species, "neon_tetra", f"Neon {index + 1}", index))
    sim = AquariumSimulation(species, state)
    sim.advance(8 * 3600)
    assert state["welfare"]["status"] != "critical"
    assert not any(issue["key"] == "group_neon_tetra" for issue in state["welfare"]["issues"])
    assert min(a["social_satisfaction"] for a in state["animals"]) >= 1.0


def test_oxygen_and_ammonia_explanations() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    state["water"]["oxygen_mg_l"] = 3.5
    state["water"]["ammonia_mg_l"] = 0.5
    sim.advance(3600)
    titles = [event["title"] for event in state["events"][:5]]
    assert "Dissolved oxygen is low" in titles
    assert "Ammonia is dangerous" in titles


def test_command_persistence_shape() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / "aquarium_state.json"
        path.write_text(json.dumps(state), encoding="utf-8")
        restored = json.loads(path.read_text(encoding="utf-8"))
    assert restored["schema_version"] == 1
    assert restored["animals"] == []


def test_invalid_aquarium_index_is_recovered() -> None:
    import living_waters_daemon as daemon

    species = load_species(ROOT / "data/species/freshwater_v1.json")
    with tempfile.TemporaryDirectory() as temp:
        runtime = Path(temp)
        old_runtime = daemon.RUNTIME
        old_state_path = daemon.STATE_PATH
        old_aquariums_dir = daemon.AQUARIUMS_DIR
        old_index_path = daemon.INDEX_PATH
        try:
            daemon.RUNTIME = runtime
            daemon.STATE_PATH = runtime / "aquarium_state.json"
            daemon.AQUARIUMS_DIR = runtime / "aquariums"
            daemon.INDEX_PATH = daemon.AQUARIUMS_DIR / "index.json"
            daemon.AQUARIUMS_DIR.mkdir(parents=True)
            daemon.INDEX_PATH.write_text("null", encoding="utf-8")
            index = daemon.load_aquarium_index(species)
            assert index["aquariums"]
            assert daemon.INDEX_PATH.exists()
            assert list(daemon.AQUARIUMS_DIR.glob("invalid-index-*.json"))
        finally:
            daemon.RUNTIME = old_runtime
            daemon.STATE_PATH = old_state_path
            daemon.AQUARIUMS_DIR = old_aquariums_dir
            daemon.INDEX_PATH = old_index_path


def test_scape_items_change_biology() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    before = state["aquarium"]["nitrate_uptake"]
    sim.add_scape_item("plants", "vallisneria", 6)
    assert state["aquarium"]["nitrate_uptake"] > before
    upkeep_before = state["aquarium"]["maintenance_load"]
    sim.add_scape_item("rocks", "moss_stone", 2)
    assert state["aquarium"]["hiding_cover"] > 0.1
    assert state["aquarium"]["maintenance_load"] >= upkeep_before
    sim.reset_scape()
    assert state["aquarium"]["scape"]["layout_seed"] == 42


def test_substrate_can_be_configured() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    sim.set_substrate("planted_soil", 7.5)
    assert state["aquarium"]["substrate"] == "planted_soil"
    assert state["aquarium"]["substrate_depth_cm"] == 7.5
    assert state["biology"]["plant_health"] >= 0.95
    state["water"]["organic_waste"] = 1.0
    sim.set_substrate("bare_bottom", 4.0)
    assert state["aquarium"]["substrate"] == "bare_bottom"
    assert state["aquarium"]["substrate_depth_cm"] == 0.0
    assert state["water"]["organic_waste"] < 1.0


def test_acclimation_failure_adds_death_load() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    before_ammonia = state["water"]["ammonia_mg_l"]
    animal = sim.add_animal("ember_tetra", acclimation_minutes=0)
    assert animal is not None
    assert animal["alive"] is False
    assert "acclimation shock" in animal["cause_of_death"]
    assert animal["death_load_remaining"] > 0
    assert state["water"]["ammonia_mg_l"] > before_ammonia
    sim.advance(3600)
    assert state["water"]["organic_waste"] > 0.12


def test_filter_clogging_and_service_changes_flow() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    filter_state = state["equipment"]["filter"]
    filter_state["media"]["mechanical"]["clog"] = 0.85
    filter_state["flow"] = 0.45
    filter_state["media"]["chemical"]["carbon_remaining"] = 0.05
    sim.advance(3600)
    clogged_flow = filter_state["effective_flow"]
    assert clogged_flow < 0.3
    sim.service_filter()
    assert filter_state["media"]["mechanical"]["clog"] < 0.3
    assert filter_state["effective_flow"] <= filter_state["flow"]
    assert filter_state["media"]["chemical"]["carbon_remaining"] == 1.0
    sim.advance(300)
    assert filter_state["effective_flow"] > clogged_flow


def test_filter_bio_capacity_depends_on_maturity() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    mature_state = default_state(species)
    immature_state = default_state(species)
    mature = AquariumSimulation(species, mature_state)
    immature = AquariumSimulation(species, immature_state)
    immature_state["equipment"]["filter"]["maturity"] = 0.12
    immature_state["equipment"]["filter"]["media"]["biological"]["maturity"] = 0.12
    mature_state["water"]["ammonia_mg_l"] = 0.7
    immature_state["water"]["ammonia_mg_l"] = 0.7
    mature.advance(12 * 3600)
    immature.advance(12 * 3600)
    assert mature_state["water"]["ammonia_mg_l"] < immature_state["water"]["ammonia_mg_l"]


def test_planning_weight_and_placement_risks() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    state["planning"]["stand_rating_kg"] = 40
    state["planning"]["dedicated_stand"] = False
    state["planning"]["direct_sunlight_hours"] = 2.0
    sim = AquariumSimulation(species, state)
    sim.advance(60)
    titles = [issue["title"] for issue in state["planning"]["issues"]]
    assert "Stand may be unsafe" in titles
    assert "Direct sunlight risk" in titles
    assert state["planning"]["estimated_total_weight_kg"] > state["aquarium"]["gross_litres"]


def test_fishless_cycle_blocks_stocking_until_clear() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    sim.dose_ammonia(1.0)
    assert state["cycle"]["ready_for_animals"] is False
    state["animals"].append(animal(species, "neon_tetra", "Too Soon", 1))
    sim.advance(3600)
    assert state["welfare"]["status"] == "critical"
    assert any(issue["key"] == "uncycled_tank" for issue in state["welfare"]["issues"])


def test_weekly_maintenance_reduces_waste_and_logs_dates() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    state["water"]["organic_waste"] = 2.0
    state["water"]["turbidity"] = 0.8
    sim.weekly_maintenance()
    assert state["water"]["organic_waste"] < 1.5
    assert state["water"]["turbidity"] < 0.5
    assert state["maintenance"]["water_conditioner_used"] is True


def test_untreated_water_change_adds_chlorine_risk() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    state["animals"].append(animal(species, "neon_tetra", "Chlorine Test", 1))
    sim = AquariumSimulation(species, state)
    sim.water_change(0.3, conditioner_used=False)
    sim.advance(60)
    assert state["water"]["chlorine_mg_l"] > 0
    assert any(issue["key"] == "chlorine" for issue in state["welfare"]["issues"])


def test_animals_have_individual_variation() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    first = animal(species, "neon_tetra", "First", 1)
    second = animal(species, "neon_tetra", "Second", 2)
    assert first["genetic_resilience"] != second["genetic_resilience"]
    assert first["stress_sensitivity"] != second["stress_sensitivity"]
    assert first["appetite_bias"] != second["appetite_bias"]


def test_water_test_readings_have_realistic_variance() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    state["randomness"]["seed"] = 12345
    state["water"]["ammonia_mg_l"] = 0.42
    state["water"]["nitrite_mg_l"] = 0.18
    sim = AquariumSimulation(species, state)
    sim.test_water()
    readings = state["last_test_results"]
    assert readings["confidence"] == "normal kit variance"
    assert abs(readings["ammonia_mg_l"] - 0.42) < 0.08
    assert readings["ammonia_mg_l"] != 0.42
    assert abs(readings["ph"] - state["water"]["ph"]) <= 0.08


def test_disease_risk_depends_on_stress_and_dirty_water() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    state["randomness"]["seed"] = 99
    sick = animal(species, "neon_tetra", "At Risk", 1)
    sick["immune_condition"] = 0.05
    sick["chronic_stress"] = 0.8
    sick["latent_pathogen_load"] = 0.9
    sick["disease_resistance"] = 0.35
    state["animals"].append(sick)
    state["water"]["ammonia_mg_l"] = 0.5
    state["water"]["organic_waste"] = 3.0
    state["water"]["turbidity"] = 0.8
    sim = AquariumSimulation(species, state)
    sim._maybe_update_disease(sick, 72)
    assert sick["disease"] == "opportunistic infection"
    assert state["randomness"]["latest"].endswith("opportunistic infection")


def test_saltwater_switch_species_and_reefscape_rules() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    sim.switch_system("saltwater")
    assert state["water"]["system"] == "saltwater"
    assert state["water"]["salinity_ppt"] >= 34
    assert state["animals"] == []
    before = len(state["animals"])
    assert sim.add_animal("ember_tetra", acclimation_minutes=30) is None
    assert len(state["animals"]) == before
    marine = sim.add_animal("banggai_cardinalfish", acclimation_minutes=50)
    assert marine is not None
    assert marine["alive"] is True
    sim.reset_scape()
    assert any(coral["type"] == "zoanthids" for coral in state["aquarium"]["scape"]["corals"])


def test_scape_placement_rules_and_relocation() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    sim.place_scape_item("plants", "dwarf_hairgrass", 0.5, 0.2)
    assert not state["aquarium"]["scape"]["objects"]
    sim.place_scape_item("plants", "red_root_floaters", 0.5, 0.1)
    assert len(state["aquarium"]["scape"]["objects"]) == 1
    floater_id = state["aquarium"]["scape"]["objects"][0]["id"]
    sim.move_scape_item(floater_id, 0.6, 0.85)
    assert state["aquarium"]["scape"]["objects"][0]["y"] == 0.1
    sim.switch_system("saltwater")
    sim.place_scape_item("corals", "torch_coral", 0.55, 0.82)
    assert any(obj["type"] == "torch_coral" for obj in state["aquarium"]["scape"]["objects"])
    sim.clear_scape()
    assert state["aquarium"]["scape"]["objects"] == []
    assert state["aquarium"]["scape"]["plants"] == []


def test_feeding_competition_can_leave_shy_fish_hungry() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    dominant = animal(species, "zebra_danio", "Dominant", 1)
    shy = animal(species, "fancy_guppy", "Shy", 2)
    dominant["feeding_rank"] = 1.0
    dominant["boldness"] = 1.0
    dominant["hunger"] = 0.9
    shy["feeding_rank"] = 0.1
    shy["boldness"] = 0.1
    shy["hunger"] = 0.9
    state["animals"] = [dominant, shy]
    sim = AquariumSimulation(species, state)
    shares = sim._feeding_distribution([dominant, shy], 0.5)
    assert shares[dominant["id"]] > shares[shy["id"]] * 2
    sim.feed(0.8)
    sim.advance(3 * 3600)
    assert dominant["hunger"] <= shy["hunger"]


def test_equipment_failure_and_service_recovery() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    filter_state = state["equipment"]["filter"]
    filter_state["media"]["mechanical"]["clog"] = 0.92
    filter_state["health"] = 0.55
    sim.advance(4 * 3600)
    assert filter_state["failure_mode"] == "impeller strain"
    assert filter_state["noise"] > 0.2
    sim.service_filter()
    assert filter_state["failure_mode"] == ""
    assert filter_state["media"]["mechanical"]["clog"] < 0.3
    sim.set_equipment("air_pump", True, 0.9)
    assert state["equipment"]["air_pump"]["output"] == 0.9


def test_plants_melt_when_root_feeders_have_bad_substrate() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    state["aquarium"]["substrate"] = "bare_bottom"
    state["aquarium"]["substrate_depth_cm"] = 0.0
    state["aquarium"]["scape"]["plants"] = [{"type": "amazon_sword", "quantity": 4, "health": 0.42}]
    state["water"]["nitrate_mg_l"] = 1.0
    state["water"]["phosphate_mg_l"] = 0.02
    sim = AquariumSimulation(species, state)
    sim.advance(72 * 3600)
    plant = state["aquarium"]["scape"]["plants"][0]
    assert plant["health"] < 0.42
    assert any("melting" in event["title"] for event in state["events"])


def test_nursery_recruits_when_conditions_remain_stable() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    state["nursery"] = [{"species_id": "fancy_guppy", "count": 3, "age_days": 44.9, "survival_chance": 0.9, "created_at": "test"}]
    before = len(state["animals"])
    sim.advance(6 * 3600)
    assert len(state["animals"]) > before
    assert state["nursery"] == []


def main() -> int:
    tests = [
        test_nitrogen_cycle_and_water_change,
        test_water_change_shock_depends_on_replacement_water,
        test_phosphate_can_be_reduced_by_water_change_and_media,
        test_plants_and_macroalgae_use_some_phosphate,
        test_leftover_food_mineralizes_slowly,
        test_day_night_clock_fields_are_published,
        test_source_water_and_conditioner_affect_water_changes,
        test_small_maintenance_actions_reduce_visible_pressure,
        test_overcleaned_filter_disturbs_biofilter,
        test_symptoms_publish_visible_tank_state,
        test_tank_maturity_changes_with_time_and_neglect,
        test_fish_routine_reflects_surface_stress,
        test_default_tank_starts_empty,
        test_clear_tank_setup_is_empty_uncycled_and_sized,
        test_legacy_preplaced_animals_are_cleared,
        test_schooling_and_tank_size_stress,
        test_lone_schooling_fish_declines_from_social_deprivation,
        test_proper_neon_school_avoids_social_crisis,
        test_oxygen_and_ammonia_explanations,
        test_command_persistence_shape,
        test_invalid_aquarium_index_is_recovered,
        test_scape_items_change_biology,
        test_substrate_can_be_configured,
        test_acclimation_failure_adds_death_load,
        test_filter_clogging_and_service_changes_flow,
        test_filter_bio_capacity_depends_on_maturity,
        test_planning_weight_and_placement_risks,
        test_fishless_cycle_blocks_stocking_until_clear,
        test_weekly_maintenance_reduces_waste_and_logs_dates,
        test_untreated_water_change_adds_chlorine_risk,
        test_animals_have_individual_variation,
        test_water_test_readings_have_realistic_variance,
        test_disease_risk_depends_on_stress_and_dirty_water,
        test_saltwater_switch_species_and_reefscape_rules,
        test_scape_placement_rules_and_relocation,
        test_feeding_competition_can_leave_shy_fish_hungry,
        test_equipment_failure_and_service_recovery,
        test_plants_melt_when_root_feeders_have_bad_substrate,
        test_nursery_recruits_when_conditions_remain_stable,
    ]
    for test in tests:
        test()
        print(f"PASS {test.__name__}")
    print("All Living Waters simulation tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
