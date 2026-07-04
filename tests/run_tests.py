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


def test_food_profiles_change_waste_pressure() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    clean_state = clear_state(species, "Pellet Test", "freshwater", 80)
    rich_state = clear_state(species, "Frozen Food Test", "freshwater", 80)
    clean_state["randomness"]["noise"] = 0.0
    rich_state["randomness"]["noise"] = 0.0
    clean_sim = AquariumSimulation(species, clean_state)
    rich_sim = AquariumSimulation(species, rich_state)
    clean_sim.feed(1.0, "micro_pellet")
    rich_sim.feed(1.0, "frozen_invertebrates")
    clean_sim.advance(72 * 3600)
    rich_sim.advance(72 * 3600)
    assert rich_state["water"]["phosphate_mg_l"] > clean_state["water"]["phosphate_mg_l"]
    assert rich_state["water"]["organic_waste"] > clean_state["water"]["organic_waste"]
    assert rich_state["food"]["clouding"] > clean_state["food"]["clouding"]


def test_diet_match_distinguishes_grazers_from_meaty_food() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = clear_state(species, "Diet Match Test", "freshwater", 45)
    sim = AquariumSimulation(species, state)
    shrimp_spec = species["cherry_shrimp"]
    sim.feed(0.3, "algae_wafer")
    algae_match = sim._diet_match(shrimp_spec, state["food"])
    sim.feed(0.3, "frozen_invertebrates")
    frozen_match = sim._diet_match(shrimp_spec, state["food"])
    assert algae_match > 0.85
    assert frozen_match < algae_match * 0.55


def test_sinking_food_reaches_bottom_fish_better_than_flake() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = clear_state(species, "Feeding Zone Test", "freshwater", 100)
    cory = animal(species, "peppered_cory", "Cory", 21)
    danio = animal(species, "zebra_danio", "Danio", 22)
    for fish in (cory, danio):
        fish["hunger"] = 0.92
        fish["acute_stress"] = 0.0
    state["animals"] = [cory, danio]
    sim = AquariumSimulation(species, state)
    sim.feed(0.4, "community_flake")
    flake_share = sim._feeding_distribution(state["animals"], 0.4)[cory["id"]]
    sim.feed(0.4, "sinking_wafer")
    wafer_share = sim._feeding_distribution(state["animals"], 0.4)[cory["id"]]
    assert wafer_share > flake_share * 1.35
    assert wafer_share > 0.2


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


def test_algae_ecology_has_distinct_drivers_and_effects() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    state["water"]["nitrate_mg_l"] = 42.0
    state["water"]["phosphate_mg_l"] = 1.1
    state["water"]["organic_waste"] = 2.0
    state["water"]["detritus"] = 0.72
    state["water"]["redox_mv"] = 215.0
    state["water"]["silicate_mg_l"] = 1.4
    state["water"]["co2_mg_l"] = 18.0
    state["stability"]["ph_swing_24h"] = 0.55
    state["maturity"]["seasoning"] = 0.08
    before = dict(state["algae_ecology"])
    before_oxygen = state["water"]["oxygen_mg_l"]
    sim._update_algae_ecology(96.0, True, 12.0, 2.0, 0.08, {"plant_cover": 0.05, "algae_control": 0.02})
    algae = state["algae_ecology"]
    assert algae["green_water"] > before["green_water"]
    assert algae["hair_algae"] > before["hair_algae"]
    assert algae["cyanobacteria"] > before["cyanobacteria"]
    assert algae["black_beard_algae"] > before["black_beard_algae"]
    assert algae["brown_diatoms"] > before["brown_diatoms"]
    assert state["water"]["oxygen_mg_l"] < before_oxygen
    assert state["biology"]["algae"] > 0.1


def test_scraping_and_grazing_affect_specific_algae_types() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    state["algae_ecology"].update({
        "glass_film": 0.8,
        "brown_diatoms": 0.7,
        "hair_algae": 0.62,
        "cyanobacteria": 0.28,
        "black_beard_algae": 0.24,
    })
    state["maturity"]["glass_algae"] = 0.8
    state["maturity"]["diatom_film"] = 0.7
    sim = AquariumSimulation(species, state)
    before_hair = state["algae_ecology"]["hair_algae"]
    sim.scrape_algae()
    assert state["algae_ecology"]["glass_film"] < 0.3
    assert state["algae_ecology"]["brown_diatoms"] < 0.5
    assert state["algae_ecology"]["hair_algae"] < before_hair
    grazer = animal(species, "otocinclus", "Grazer", 9)
    grazer["hunger"] = 0.8
    state["animals"].append(grazer)
    before_hair_after_scrape = state["algae_ecology"]["hair_algae"]
    sim._cleanup_grazing(state["animals"], 72.0)
    assert state["algae_ecology"]["hair_algae"] < before_hair_after_scrape
    assert state["biology"]["cleanup_export"] > 0


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


def test_tiny_life_web_grows_from_biofilm_and_leftovers() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = clear_state(species, "Micro Life", "freshwater", 70)
    state["randomness"]["noise"] = 0.0
    state["cycle"]["days_running"] = 80
    state["maturity"]["biofilm"] = 0.62
    state["maturity"]["infusoria"] = 0.08
    state["maturity"]["copepods"] = 0.05
    state["maturity"]["pest_snails"] = 0.10
    state["aquarium"]["plant_cover"] = 0.55
    state["food"]["available"] = 0.8
    state["food"]["decaying"] = 0.5
    state["water"]["organic_waste"] = 0.9
    sim = AquariumSimulation(species, state)
    before_infusoria = state["maturity"]["infusoria"]
    before_copepods = state["maturity"]["copepods"]
    before_snails = state["maturity"]["pest_snails"]
    before_food = state["food"]["available"]
    sim.advance(72 * 3600)
    assert state["maturity"]["infusoria"] > before_infusoria
    assert state["maturity"]["copepods"] > before_copepods
    assert state["maturity"]["pest_snails"] > before_snails
    assert state["food"]["available"] < before_food
    assert state["symptoms"]["visible_microfauna"] > 0.1


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
    assert sick["disease"] == "gill inflammation"
    assert state["randomness"]["latest"].endswith("gill inflammation")


def test_named_disease_selection_uses_cause() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    fish = animal(species, "fancy_guppy", "Nipped", 2)
    fish["injury"] = 0.5
    disease, _details = sim._select_disease(fish, 0.0, 0.2, 0.0, fish["injury"], 0.0)
    assert disease == "fin rot"
    fish["injury"] = 0.0
    fish["latent_pathogen_load"] = 0.08
    disease, _details = sim._select_disease(fish, 0.0, 0.0, 0.0, 0.0, 0.35)
    assert disease == "ich outbreak"


def test_pathogen_ecology_builds_from_carriers_and_dirty_water() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    carrier = animal(species, "neon_tetra", "Carrier", 3)
    carrier["parasite_load"] = 0.65
    carrier["latent_pathogen_load"] = 0.35
    state["animals"].append(carrier)
    state["water"]["organic_waste"] = 2.2
    state["water"]["detritus"] = 0.7
    state["water"]["redox_mv"] = 220
    state["equipment"]["filter"]["enabled"] = False
    state["maturity"]["beneficial_film"] = 0.05
    state["disease_ecology"]["free_swimming_parasites"] = 0.02
    state["disease_ecology"]["bacterial_bloom"] = 0.04
    before_free = state["disease_ecology"]["free_swimming_parasites"]
    before_bloom = state["disease_ecology"]["bacterial_bloom"]
    AquariumSimulation(species, state).advance(48 * 3600, offline=True)
    assert state["disease_ecology"]["free_swimming_parasites"] > before_free
    assert state["disease_ecology"]["bacterial_bloom"] > before_bloom
    assert state["water"]["parasite_pressure"] > 0.025
    assert state["symptoms"]["outbreak_pressure"] > 0.0


def test_quarantine_reduces_display_shedding() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    display_state = default_state(species)
    quarantine_state = default_state(species)
    for state, quarantined in ((display_state, False), (quarantine_state, True)):
        sick = animal(species, "fancy_guppy", "Sick", 4)
        sick["disease"] = "white spot outbreak"
        sick["disease_stage"] = "visible"
        sick["parasite_load"] = 0.72
        sick["immune_condition"] = 0.2
        sick["quarantined"] = quarantined
        sick["quarantine_days_remaining"] = 14.0 if quarantined else 0.0
        state["animals"].append(sick)
        state["randomness"]["noise"] = 0.0
    display_sim = AquariumSimulation(species, display_state)
    quarantine_sim = AquariumSimulation(species, quarantine_state)
    display_sim._update_disease_ecology(24.0, display_state["animals"], 1.0)
    quarantine_sim._update_disease_ecology(24.0, quarantine_state["animals"], 1.0)
    quarantine_sim._update_symptoms()
    assert display_state["disease_ecology"]["free_swimming_parasites"] > quarantine_state["disease_ecology"]["free_swimming_parasites"]
    assert quarantine_state["symptoms"]["quarantined_animals"] == 1


def test_treatment_lowers_pathogens_but_disturbs_microfauna() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    state["disease_ecology"]["free_swimming_parasites"] = 0.72
    state["disease_ecology"]["bacterial_bloom"] = 0.62
    state["water"]["parasite_pressure"] = 0.55
    state["water"]["bacterial_pressure"] = 0.58
    state["maturity"]["microfauna"] = 0.66
    state["maturity"]["copepods"] = 0.5
    before_microfauna = state["maturity"]["microfauna"]
    before_copepods = state["maturity"]["copepods"]
    sim = AquariumSimulation(species, state)
    sim.treat_outbreak(strength=0.65, days=5)
    assert state["disease_ecology"]["free_swimming_parasites"] < 0.72
    assert state["disease_ecology"]["bacterial_bloom"] < 0.62
    assert state["maturity"]["microfauna"] < before_microfauna
    assert state["maturity"]["copepods"] < before_copepods
    assert state["disease_ecology"]["treatment_days_remaining"] == 5


def test_evaporation_top_off_and_skimmer_change_reef_water() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = clear_state(species, "Reef Evap", "saltwater", 120)
    sim = AquariumSimulation(species, state)
    state["equipment"]["protein_skimmer"]["enabled"] = True
    state["equipment"]["protein_skimmer"]["output"] = 0.8
    state["water"]["organic_waste"] = 1.4
    before_level = state["water"]["water_level"]
    before_salinity = state["water"]["salinity_ppt"]
    before_waste = state["water"]["organic_waste"]
    sim.advance(48 * 3600)
    assert state["water"]["water_level"] < before_level
    assert state["water"]["salinity_ppt"] > before_salinity
    assert state["water"]["organic_waste"] < before_waste
    assert state["equipment"]["protein_skimmer"]["cup_fullness"] > 0
    sim.top_off()
    assert state["water"]["water_level"] > 0.98
    assert state["water"]["salinity_ppt"] < 36.5


def test_hardscape_materials_change_water_chemistry() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = clear_state(species, "Wood Chemistry", "freshwater", 80)
    sim = AquariumSimulation(species, state)
    state["aquarium"]["scape"]["wood"] = [{"type": "root_driftwood", "quantity": 10, "scale": 1.0}]
    before_tannins = state["water"]["tannins"]
    before_ph = state["water"]["ph"]
    sim._tick(48 * 3600)
    assert state["water"]["tannins"] > before_tannins
    assert state["water"]["ph"] < before_ph
    assert state["aquarium"]["soft_water"] > 0.2

    reef = clear_state(species, "Rock Chemistry", "saltwater", 120)
    reef_sim = AquariumSimulation(species, reef)
    reef["aquarium"]["scape"]["rocks"] = [{"type": "live_rock", "quantity": 8, "scale": 1.0}]
    before_alk = reef["water"]["alkalinity_dkh"]
    before_calcium = reef["water"]["calcium_mg_l"]
    reef_sim._tick(48 * 3600)
    assert reef["water"]["alkalinity_dkh"] > before_alk
    assert reef["water"]["calcium_mg_l"] > before_calcium


def test_mineral_dosing_replenishes_reef_reserves() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = clear_state(species, "Dose Reef", "saltwater", 120)
    sim = AquariumSimulation(species, state)
    state["water"]["alkalinity_dkh"] = 5.0
    state["water"]["calcium_mg_l"] = 330.0
    state["water"]["magnesium_mg_l"] = 1000.0
    state["water"]["trace_elements"] = 0.2
    sim.dose_minerals()
    assert state["water"]["alkalinity_dkh"] > 5.0
    assert state["water"]["calcium_mg_l"] > 330.0
    assert state["water"]["magnesium_mg_l"] > 1000.0
    assert state["water"]["trace_elements"] > 0.2


def test_animal_personality_fields_drive_routines() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    fish = animal(species, "honey_gourami", "Curious", 5)
    fish["curiosity"] = 0.95
    fish["acute_stress"] = 0.03
    fish["hunger"] = 0.1
    state["animals"].append(fish)
    sim = AquariumSimulation(species, state)
    sim.advance(3600)
    assert "curiosity" in fish
    assert "sleep_x" in fish
    assert fish["routine"] not in {"", None}
    assert fish["behavior"] not in {"", None}


def test_tiny_life_supports_natural_foraging() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    rich_state = default_state(species)
    poor_state = default_state(species)
    rich_fish = animal(species, "neon_tetra", "Forager", 31)
    poor_fish = animal(species, "neon_tetra", "Hungry", 31)
    for state, fish in ((rich_state, rich_fish), (poor_state, poor_fish)):
        state["randomness"]["noise"] = 0.0
        fish["hunger"] = 0.78
        fish["acute_stress"] = 0.0
        state["animals"] = [fish]
        state["food"]["available"] = 0.0
    rich_state["maturity"]["infusoria"] = 0.82
    rich_state["maturity"]["copepods"] = 0.78
    poor_state["maturity"]["infusoria"] = 0.02
    poor_state["maturity"]["copepods"] = 0.01
    AquariumSimulation(species, rich_state).advance(8 * 3600)
    AquariumSimulation(species, poor_state).advance(8 * 3600)
    assert rich_fish["hunger"] < poor_fish["hunger"]
    assert rich_fish["foraging_support"] > 0.3


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


def test_aged_light_reduces_effective_growth_output() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    fresh_state = clear_state(species, "Fresh Lamp", "freshwater", 90)
    aged_state = clear_state(species, "Old Lamp", "freshwater", 90)
    for state in (fresh_state, aged_state):
        state["randomness"]["noise"] = 0.0
        state["aquarium"]["scape"]["plants"] = [{"type": "hornwort", "quantity": 18, "health": 0.72}]
        state["water"]["nitrate_mg_l"] = 18.0
        state["water"]["phosphate_mg_l"] = 0.35
        state["water"]["trace_elements"] = 0.8
        state["equipment"]["light"]["hours_per_day"] = 7.0
        state["equipment"]["light"]["health"] = 0.96
        state["equipment"]["light"]["plant_spectrum"] = 0.86
    fresh_state["equipment"]["light"]["lamp_age_days"] = 30.0
    aged_state["equipment"]["light"]["lamp_age_days"] = 720.0
    fresh_sim = AquariumSimulation(species, fresh_state)
    aged_sim = AquariumSimulation(species, aged_state)
    fresh_sim.advance(48 * 3600)
    aged_sim.advance(48 * 3600)
    assert aged_state["equipment"]["light"]["effective_spectrum"] < fresh_state["equipment"]["light"]["effective_spectrum"] * 0.75
    assert aged_state["equipment"]["light"]["par_output"] < fresh_state["equipment"]["light"]["par_output"] * 0.72
    assert aged_state["aquarium"]["scape"]["plants"][0]["health"] <= fresh_state["aquarium"]["scape"]["plants"][0]["health"]


def test_heater_calibration_offset_changes_temperature() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    normal_state = clear_state(species, "Normal Heater", "freshwater", 80)
    offset_state = clear_state(species, "Offset Heater", "freshwater", 80)
    for state in (normal_state, offset_state):
        state["randomness"]["noise"] = 0.0
        state["water"]["temperature_c"] = 21.0
        state["equipment"]["heater"]["enabled"] = True
        state["equipment"]["heater"]["target_c"] = 24.0
        state["equipment"]["heater"]["health"] = 0.96
    normal_state["equipment"]["heater"]["calibration_offset_c"] = 0.0
    offset_state["equipment"]["heater"]["calibration_offset_c"] = 1.1
    normal_sim = AquariumSimulation(species, normal_state)
    offset_sim = AquariumSimulation(species, offset_state)
    normal_sim.advance(8 * 3600)
    offset_sim.advance(8 * 3600)
    assert offset_state["water"]["temperature_c"] > normal_state["water"]["temperature_c"] + 0.25


def test_skimmer_neck_fouling_reduces_export() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    clean_state = clear_state(species, "Clean Skimmer", "saltwater", 120)
    fouled_state = clear_state(species, "Fouled Skimmer", "saltwater", 120)
    for state in (clean_state, fouled_state):
        state["randomness"]["noise"] = 0.0
        state["water"]["organic_waste"] = 1.2
        state["water"]["dissolved_organics"] = 0.8
        state["equipment"]["protein_skimmer"]["enabled"] = True
        state["equipment"]["protein_skimmer"]["health"] = 0.95
        state["equipment"]["protein_skimmer"]["output"] = 0.75
        state["equipment"]["protein_skimmer"]["cup_fullness"] = 0.1
    clean_state["equipment"]["protein_skimmer"]["neck_fouling"] = 0.0
    fouled_state["equipment"]["protein_skimmer"]["neck_fouling"] = 0.85
    clean_sim = AquariumSimulation(species, clean_state)
    fouled_sim = AquariumSimulation(species, fouled_state)
    clean_sim.advance(8 * 3600)
    fouled_sim.advance(8 * 3600)
    assert clean_state["equipment"]["protein_skimmer"]["effective_output"] > fouled_state["equipment"]["protein_skimmer"]["effective_output"]
    assert clean_state["water"]["organic_waste"] < fouled_state["water"]["organic_waste"]


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


def test_microfauna_improves_fry_survival_chance() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    rich_state = default_state(species)
    poor_state = default_state(species)
    for state in (rich_state, poor_state):
        state["randomness"]["noise"] = 0.0
        state["nursery"] = [{"species_id": "fancy_guppy", "count": 6, "age_days": 12.0, "survival_chance": 0.45, "created_at": "test"}]
        state["water"]["ammonia_mg_l"] = 0.0
        state["water"]["nitrite_mg_l"] = 0.0
        state["water"]["nitrate_mg_l"] = 10.0
    rich_state["maturity"]["infusoria"] = 0.85
    rich_state["maturity"]["copepods"] = 0.74
    poor_state["maturity"]["infusoria"] = 0.01
    poor_state["maturity"]["copepods"] = 0.01
    AquariumSimulation(species, rich_state).advance(24 * 3600)
    AquariumSimulation(species, poor_state).advance(24 * 3600)
    assert rich_state["nursery"][0]["survival_chance"] > poor_state["nursery"][0]["survival_chance"]
    assert rich_state["nursery"][0]["live_food_support"] > poor_state["nursery"][0]["live_food_support"]


def test_free_ammonia_depends_on_ph_and_temperature() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    low_state = default_state(species)
    high_state = default_state(species)
    low_state["water"]["ammonia_mg_l"] = 0.8
    low_state["water"]["ph"] = 6.6
    low_state["water"]["temperature_c"] = 22.0
    high_state["water"]["ammonia_mg_l"] = 0.8
    high_state["water"]["ph"] = 8.6
    high_state["water"]["temperature_c"] = 28.0
    AquariumSimulation(species, low_state).advance(1800)
    AquariumSimulation(species, high_state).advance(1800)
    assert high_state["water"]["free_ammonia_mg_l"] > low_state["water"]["free_ammonia_mg_l"] * 15
    assert high_state["water"]["nitrogen_toxicity_index"] > low_state["water"]["nitrogen_toxicity_index"]


def test_deep_dirty_substrate_builds_hypoxia_and_low_redox() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    state["aquarium"]["substrate"] = "fine_sand"
    state["aquarium"]["substrate_depth_cm"] = 8.5
    state["aquarium"]["flow_break"] = 0.35
    state["water"]["detritus"] = 0.82
    state["water"]["organic_waste"] = 2.4
    state["water"]["dissolved_organics"] = 1.4
    state["water"]["surface_film"] = 0.6
    state["water"]["oxygen_mg_l"] = 5.2
    state["water"]["redox_mv"] = 390.0
    state["equipment"]["filter"]["flow"] = 0.08
    state["equipment"]["filter"]["media"]["mechanical"]["clog"] = 0.9
    sim = AquariumSimulation(species, state)
    before_redox = state["water"]["redox_mv"]
    sim.advance(96 * 3600)
    assert state["maturity"]["substrate_hypoxia"] > 0.08
    assert state["maturity"]["anaerobic_pocket_risk"] > 0.08
    assert state["water"]["redox_mv"] < before_redox
    assert state["chemistry"]["substrate_warning"] or state["symptoms"]["substrate_hypoxia"] > 0.08


def test_parameter_swings_leave_stability_debt_and_welfare_risk() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    fish = animal(species, "neon_tetra", "Swing", 11)
    state["animals"] = [fish]
    sim = AquariumSimulation(species, state)
    sim.water_change(
        0.55,
        conditioner_used=True,
        replacement_temp_c=14.0,
        replacement_ph=8.7,
        replacement_gh_dgh=22.0,
        disturbed_substrate=True,
    )
    assert state["stability"]["temperature_swing_24h"] > 4.0
    assert state["stability"]["ph_swing_24h"] > 0.5
    assert state["stability"]["stability_score"] < 0.72
    sim._summarize()
    assert any(issue["key"] == "unstable_parameters" for issue in state["welfare"]["issues"])


def test_cleanup_animals_graze_algae_detritus_and_leftovers() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    state["randomness"]["noise"] = 0.0
    state["animals"] = [
        animal(species, "otocinclus", "Oto", 12),
        animal(species, "cherry_shrimp", "Shrimp", 13),
        animal(species, "bristlenose_pleco", "Pleco", 14),
    ]
    state["biology"]["algae"] = 0.72
    state["maturity"]["glass_algae"] = 0.62
    state["water"]["detritus"] = 0.55
    state["food"]["available"] = 0.75
    sim = AquariumSimulation(species, state)
    before_algae = state["biology"]["algae"]
    before_detritus = state["water"]["detritus"]
    before_food = state["food"]["available"]
    sim.advance(24 * 3600)
    assert state["biology"]["grazing_pressure"] > 0.2
    assert state["biology"]["algae"] < before_algae
    assert state["water"]["detritus"] < before_detritus
    assert state["food"]["available"] < before_food
    assert state["biology"]["cleanup_export"] > 0


def test_metabolic_load_depends_on_temperature_activity_and_condition() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    cool_state = default_state(species)
    warm_state = default_state(species)
    cool_fish = animal(species, "zebra_danio", "Cool", 15)
    warm_fish = animal(species, "zebra_danio", "Warm", 15)
    cool_fish["hunger"] = 0.85
    warm_fish["hunger"] = 0.2
    warm_fish["acute_stress"] = 0.45
    cool_state["animals"] = [cool_fish]
    warm_state["animals"] = [warm_fish]
    cool_state["water"]["temperature_c"] = 20.0
    warm_state["water"]["temperature_c"] = 28.0
    cool_sim = AquariumSimulation(species, cool_state)
    warm_sim = AquariumSimulation(species, warm_state)
    assert warm_sim._metabolic_bioload([warm_fish]) > cool_sim._metabolic_bioload([cool_fish])


def test_filter_service_creates_temporary_maintenance_residue() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    state["water"]["turbidity"] = 0.0
    state["equipment"]["filter"]["media"]["mechanical"]["clog"] = 0.1
    sim = AquariumSimulation(species, state)
    sim.service_filter()
    assert state["action_residue"]["filter_biofilm_shed"] > 0.05
    assert state["action_residue"]["suspended_debris"] > 0.03
    before_clog = state["equipment"]["filter"]["media"]["mechanical"]["clog"]
    sim.advance(6 * 3600)
    assert state["symptoms"]["maintenance_haze"] > 0.0
    assert state["equipment"]["filter"]["media"]["mechanical"]["clog"] > before_clog
    assert state["action_residue"]["filter_biofilm_shed"] < 0.08


def test_trimmed_plant_fragments_decay_if_left_in_tank() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    state["aquarium"]["scape"]["plants"] = [{"type": "vallisneria", "quantity": 80, "health": 0.88}]
    state["water"]["organic_waste"] = 0.0
    state["water"]["phosphate_mg_l"] = 0.0
    state["water"]["ammonia_mg_l"] = 0.0
    sim = AquariumSimulation(species, state)
    sim.trim_plants()
    fragments = state["action_residue"]["plant_fragments"]
    assert fragments > 0.1
    before_organics = state["water"]["organic_waste"]
    before_ammonia = state["water"]["ammonia_mg_l"]
    sim._update_action_residue(6.0)
    sim._update_symptoms()
    assert state["action_residue"]["plant_fragments"] < fragments
    assert state["water"]["organic_waste"] > before_organics
    assert state["water"]["ammonia_mg_l"] >= before_ammonia
    assert state["symptoms"]["maintenance_haze"] > 0


def test_water_testing_leaves_small_temporary_reagent_trace() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    sim.test_water()
    assert state["action_residue"]["reagent_trace"] > 0
    assert state["action_residue"]["last_action"] == "water test"
    sim.advance(2 * 3600)
    assert state["action_residue"]["reagent_trace"] < 0.025


def main() -> int:
    tests = [
        test_nitrogen_cycle_and_water_change,
        test_water_change_shock_depends_on_replacement_water,
        test_phosphate_can_be_reduced_by_water_change_and_media,
        test_plants_and_macroalgae_use_some_phosphate,
        test_leftover_food_mineralizes_slowly,
        test_food_profiles_change_waste_pressure,
        test_diet_match_distinguishes_grazers_from_meaty_food,
        test_sinking_food_reaches_bottom_fish_better_than_flake,
        test_day_night_clock_fields_are_published,
        test_source_water_and_conditioner_affect_water_changes,
        test_small_maintenance_actions_reduce_visible_pressure,
        test_overcleaned_filter_disturbs_biofilter,
        test_symptoms_publish_visible_tank_state,
        test_algae_ecology_has_distinct_drivers_and_effects,
        test_scraping_and_grazing_affect_specific_algae_types,
        test_tank_maturity_changes_with_time_and_neglect,
        test_tiny_life_web_grows_from_biofilm_and_leftovers,
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
        test_named_disease_selection_uses_cause,
        test_pathogen_ecology_builds_from_carriers_and_dirty_water,
        test_quarantine_reduces_display_shedding,
        test_treatment_lowers_pathogens_but_disturbs_microfauna,
        test_evaporation_top_off_and_skimmer_change_reef_water,
        test_hardscape_materials_change_water_chemistry,
        test_mineral_dosing_replenishes_reef_reserves,
        test_animal_personality_fields_drive_routines,
        test_tiny_life_supports_natural_foraging,
        test_saltwater_switch_species_and_reefscape_rules,
        test_scape_placement_rules_and_relocation,
        test_feeding_competition_can_leave_shy_fish_hungry,
        test_equipment_failure_and_service_recovery,
        test_aged_light_reduces_effective_growth_output,
        test_heater_calibration_offset_changes_temperature,
        test_skimmer_neck_fouling_reduces_export,
        test_plants_melt_when_root_feeders_have_bad_substrate,
        test_nursery_recruits_when_conditions_remain_stable,
        test_microfauna_improves_fry_survival_chance,
        test_free_ammonia_depends_on_ph_and_temperature,
        test_deep_dirty_substrate_builds_hypoxia_and_low_redox,
        test_parameter_swings_leave_stability_debt_and_welfare_risk,
        test_cleanup_animals_graze_algae_detritus_and_leftovers,
        test_metabolic_load_depends_on_temperature_activity_and_condition,
        test_filter_service_creates_temporary_maintenance_residue,
        test_trimmed_plant_fragments_decay_if_left_in_tank,
        test_water_testing_leaves_small_temporary_reagent_trace,
    ]
    for test in tests:
        test()
        print(f"PASS {test.__name__}")
    print("All Living Waters simulation tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
