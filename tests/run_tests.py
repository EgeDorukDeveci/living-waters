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


def test_nitrogen_cycle_and_water_change() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    state["water"]["ammonia_mg_l"] = 0.7
    sim.advance(24 * 3600)
    assert state["water"]["ammonia_mg_l"] < 0.7
    assert state["water"]["nitrate_mg_l"] > 8.0
    before = state["water"]["nitrate_mg_l"]
    sim.water_change(0.5)
    assert state["water"]["nitrate_mg_l"] < before * 0.65


def test_schooling_and_tank_size_stress() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    state["animals"] = [a for a in state["animals"] if a["species_id"] != "neon_tetra"][:]
    state["animals"].append(default_state(species)["animals"][0])
    sim = AquariumSimulation(species, state)
    sim.advance(4 * 3600)
    neon = next(a for a in state["animals"] if a["species_id"] == "neon_tetra")
    assert neon["social_satisfaction"] < 0.3
    assert neon["acute_stress"] > 0.1


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
    assert restored["animals"][0]["id"]


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


def test_saltwater_switch_species_and_reefscape_rules() -> None:
    species = load_species(ROOT / "data/species/freshwater_v1.json")
    state = default_state(species)
    sim = AquariumSimulation(species, state)
    sim.switch_system("saltwater")
    assert state["water"]["system"] == "saltwater"
    assert state["water"]["salinity_ppt"] >= 34
    assert any(animal["species_id"] == "ocellaris_clownfish" for animal in state["animals"])
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
        test_schooling_and_tank_size_stress,
        test_oxygen_and_ammonia_explanations,
        test_command_persistence_shape,
        test_scape_items_change_biology,
        test_acclimation_failure_adds_death_load,
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
