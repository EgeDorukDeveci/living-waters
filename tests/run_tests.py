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


def main() -> int:
    tests = [
        test_nitrogen_cycle_and_water_change,
        test_schooling_and_tank_size_stress,
        test_oxygen_and_ammonia_explanations,
        test_command_persistence_shape,
    ]
    for test in tests:
        test()
        print(f"PASS {test.__name__}")
    print("All Living Waters simulation tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
