from __future__ import annotations

import json
import math
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "background"))

from simulation import AquariumSimulation, default_state, load_species  # noqa: E402


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
    sim.water_change(0.5)
    assert state["water"]["nitrate_mg_l"] < before * 0.65


def test_default_tank_starts_empty() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    assert state["animals"] == []
    assert state["summary"].get("living_animals", 0) == 0
    sim.switch_system("saltwater")
    assert state["animals"] == []


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


def main() -> int:
    tests = [
        test_nitrogen_cycle_and_water_change,
        test_default_tank_starts_empty,
        test_legacy_preplaced_animals_are_cleared,
        test_schooling_and_tank_size_stress,
        test_lone_schooling_fish_declines_from_social_deprivation,
        test_proper_neon_school_avoids_social_crisis,
        test_oxygen_and_ammonia_explanations,
        test_command_persistence_shape,
        test_scape_items_change_biology,
        test_acclimation_failure_adds_death_load,
        test_filter_clogging_and_service_changes_flow,
        test_filter_bio_capacity_depends_on_maturity,
        test_planning_weight_and_placement_risks,
        test_fishless_cycle_blocks_stocking_until_clear,
        test_weekly_maintenance_reduces_waste_and_logs_dates,
        test_untreated_water_change_adds_chlorine_risk,
        test_saltwater_switch_species_and_reefscape_rules,
        test_scape_placement_rules_and_relocation,
    ]
    for test in tests:
        test()
        print(f"PASS {test.__name__}")
    print("All Living Waters simulation tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
