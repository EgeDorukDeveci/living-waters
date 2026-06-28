from __future__ import annotations

import copy
import json
import math
import random
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
MAX_OFFLINE_SECONDS = 12 * 60 * 60

PLANT_TYPES: dict[str, dict[str, Any]] = {
    "dwarf_hairgrass": {
        "name": "Dwarf hairgrass carpet",
        "zone": "foreground",
        "nitrate_uptake": 0.16,
        "oxygen_day": 0.08,
        "oxygen_night": -0.025,
        "hiding": 0.08,
        "algae_control": 0.04,
        "maintenance": 0.05,
    },
    "java_fern": {
        "name": "Java fern",
        "zone": "midground",
        "nitrate_uptake": 0.09,
        "oxygen_day": 0.04,
        "oxygen_night": -0.015,
        "hiding": 0.16,
        "algae_control": 0.03,
        "maintenance": 0.015,
    },
    "anubias": {
        "name": "Anubias",
        "zone": "hardscape",
        "nitrate_uptake": 0.055,
        "oxygen_day": 0.025,
        "oxygen_night": -0.01,
        "hiding": 0.11,
        "algae_control": 0.02,
        "maintenance": 0.01,
    },
    "vallisneria": {
        "name": "Vallisneria background",
        "zone": "background",
        "nitrate_uptake": 0.2,
        "oxygen_day": 0.105,
        "oxygen_night": -0.035,
        "hiding": 0.13,
        "algae_control": 0.06,
        "maintenance": 0.045,
    },
    "amazon_sword": {
        "name": "Amazon sword",
        "zone": "background",
        "nitrate_uptake": 0.17,
        "oxygen_day": 0.085,
        "oxygen_night": -0.028,
        "hiding": 0.15,
        "algae_control": 0.045,
        "maintenance": 0.05,
        "root_feeder": True,
    },
    "cryptocoryne_wendtii": {
        "name": "Cryptocoryne wendtii",
        "zone": "midground",
        "nitrate_uptake": 0.075,
        "oxygen_day": 0.035,
        "oxygen_night": -0.012,
        "hiding": 0.12,
        "algae_control": 0.025,
        "maintenance": 0.018,
        "root_feeder": True,
    },
    "java_moss": {
        "name": "Java moss",
        "zone": "hardscape",
        "nitrate_uptake": 0.08,
        "oxygen_day": 0.035,
        "oxygen_night": -0.015,
        "hiding": 0.18,
        "algae_control": 0.045,
        "maintenance": 0.028,
    },
    "hornwort": {
        "name": "Hornwort bunch",
        "zone": "floating_or_planted",
        "nitrate_uptake": 0.22,
        "oxygen_day": 0.09,
        "oxygen_night": -0.032,
        "hiding": 0.1,
        "algae_control": 0.09,
        "maintenance": 0.055,
    },
    "red_root_floaters": {
        "name": "Red root floaters",
        "zone": "surface",
        "nitrate_uptake": 0.18,
        "oxygen_day": 0.05,
        "oxygen_night": -0.018,
        "hiding": 0.09,
        "algae_control": 0.11,
        "maintenance": 0.035,
        "surface_shade": 0.18,
    },
    "halimeda_macroalgae": {
        "name": "Halimeda macroalgae",
        "zone": "midground",
        "system": "saltwater",
        "nitrate_uptake": 0.15,
        "oxygen_day": 0.045,
        "oxygen_night": -0.018,
        "hiding": 0.07,
        "algae_control": 0.07,
        "maintenance": 0.03,
    },
    "turtle_grass": {
        "name": "Turtle grass",
        "zone": "background",
        "system": "saltwater",
        "nitrate_uptake": 0.17,
        "oxygen_day": 0.075,
        "oxygen_night": -0.025,
        "hiding": 0.12,
        "algae_control": 0.05,
        "maintenance": 0.04,
    },
}

HARDSCAPE_TYPES: dict[str, dict[str, Any]] = {
    "river_stone": {"name": "River stone", "hiding": 0.04, "flow_break": 0.02},
    "moss_stone": {"name": "Moss stone", "hiding": 0.07, "algae_control": 0.025},
    "dragon_stone": {"name": "Dragon stone", "hiding": 0.06, "flow_break": 0.035},
    "slate_stack": {"name": "Slate stack", "hiding": 0.1, "flow_break": 0.05},
    "lava_rock": {"name": "Lava rock", "hiding": 0.08, "biofilter": 0.035, "flow_break": 0.025},
    "branch_driftwood": {"name": "Branch driftwood", "hiding": 0.11, "soft_water": 0.025},
    "root_driftwood": {"name": "Root driftwood", "hiding": 0.16, "soft_water": 0.035},
    "manzanita_branch": {"name": "Manzanita branch", "hiding": 0.12, "soft_water": 0.018},
    "live_rock": {"name": "Live rock", "system": "saltwater", "hiding": 0.18, "biofilter": 0.12, "algae_control": 0.035},
    "reef_arch": {"name": "Reef arch", "system": "saltwater", "hiding": 0.14, "biofilter": 0.08, "flow_break": 0.04},
}

CORAL_TYPES: dict[str, dict[str, Any]] = {
    "zoanthids": {"name": "Zoanthid colony", "nitrate_uptake": 0.035, "hiding": 0.04, "algae_control": 0.02, "maintenance": 0.025, "light_need": 0.55},
    "mushroom_coral": {"name": "Mushroom coral", "nitrate_uptake": 0.025, "hiding": 0.035, "algae_control": 0.015, "maintenance": 0.018, "light_need": 0.42},
    "green_star_polyps": {"name": "Green star polyps", "nitrate_uptake": 0.045, "hiding": 0.045, "algae_control": 0.02, "maintenance": 0.035, "light_need": 0.58},
    "torch_coral": {"name": "Torch coral", "nitrate_uptake": 0.02, "hiding": 0.06, "algae_control": 0.01, "maintenance": 0.06, "light_need": 0.72},
    "pulsing_xenia": {"name": "Pulsing xenia", "nitrate_uptake": 0.055, "hiding": 0.045, "algae_control": 0.018, "maintenance": 0.05, "light_need": 0.62},
    "kenya_tree_coral": {"name": "Kenya tree coral", "nitrate_uptake": 0.035, "hiding": 0.055, "algae_control": 0.015, "maintenance": 0.04, "light_need": 0.48},
}


def now_iso() -> str:
    return datetime.now().isoformat(timespec="seconds")


def load_species(path: Path) -> dict[str, dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return {item["id"]: item for item in payload["species"]}


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def range_stress(value: float, ideal: list[float], tolerated: list[float]) -> float:
    if ideal[0] <= value <= ideal[1]:
        return 0.0
    if tolerated[0] <= value <= tolerated[1]:
        edge = ideal[0] if value < ideal[0] else ideal[1]
        limit = tolerated[0] if value < ideal[0] else tolerated[1]
        return clamp(abs(value - edge) / max(0.01, abs(limit - edge)), 0.0, 1.0) * 0.45
    distance = tolerated[0] - value if value < tolerated[0] else value - tolerated[1]
    return clamp(0.55 + distance * 0.15, 0.55, 1.0)


def default_state(species: dict[str, dict[str, Any]]) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "aquarium": {
            "name": "River Room",
            "length_cm": 90.0,
            "width_cm": 40.0,
            "height_cm": 45.0,
            "gross_litres": 162.0,
            "effective_litres": 138.0,
            "substrate": "fine_sand",
            "substrate_depth_cm": 5.0,
            "plant_cover": 0.46,
            "hiding_cover": 0.42,
            "open_swimming": 0.64,
            "surface_agitation": 0.62,
            "aquascape_style": "greenscape",
            "scape": default_scape(),
        },
        "water": {
            "system": "freshwater",
            "temperature_c": 23.5,
            "ph": 6.9,
            "salinity_ppt": 0.2,
            "gh_dgh": 7.0,
            "kh_dkh": 4.0,
            "oxygen_mg_l": 7.4,
            "co2_mg_l": 4.0,
            "ammonia_mg_l": 0.0,
            "nitrite_mg_l": 0.0,
            "nitrate_mg_l": 8.0,
            "phosphate_mg_l": 0.35,
            "chlorine_mg_l": 0.0,
            "chloramine_mg_l": 0.0,
            "tds_mg_l": 180.0,
            "water_level": 1.0,
            "tannins": 0.08,
            "organic_waste": 0.12,
            "turbidity": 0.08,
            "surface_film": 0.04,
            "detritus": 0.08,
        },
        "biology": {
            "ammonia_bacteria": 0.86,
            "nitrite_bacteria": 0.84,
            "plant_health": 0.91,
            "algae": 0.12,
        },
        "equipment": {
            "filter": default_filter(),
            "heater": {"enabled": True, "health": 0.98, "target_c": 23.5, "placement_near_flow": True, "thermometer_present": True},
            "light": {"enabled": True, "health": 0.99, "hours_per_day": 8.0, "start_hour": 10.0, "timer_enabled": True, "plant_spectrum": 0.82},
            "air_pump": {"enabled": True, "health": 0.97, "output": 0.5},
            "protein_skimmer": {"enabled": False, "health": 0.95, "output": 0.0, "cup_fullness": 0.0},
            "auto_top_off": {"enabled": False, "health": 0.96, "reservoir_litres": 5.0},
            "checklist": {
                "tank": True,
                "filter": True,
                "heater": True,
                "thermometer": True,
                "light": True,
                "substrate": True,
                "water_conditioner": True,
                "test_kit": True,
                "siphon": True,
                "dedicated_stand": True,
                "co2_system": False,
                "auto_feeder": False,
                "protein_skimmer": False,
                "auto_top_off": False,
            },
        },
        "planning": default_planning(162.0),
        "cycle": default_cycle(),
        "maintenance": default_maintenance(),
        "source_water": default_source_water("freshwater"),
        "maturity": default_maturity(35.0),
        "randomness": default_randomness(),
        "last_test_results": {},
        "animals": [],
        "food": {"available": 0.0, "decaying": 0.0, "last_fed": now_iso()},
        "clock": {
            "simulated_at": now_iso(),
            "last_real_timestamp": time.time(),
            "total_simulated_seconds": 0.0,
            "speed": 1.0,
            "local_hour": datetime.now().hour + datetime.now().minute / 60.0,
            "day_phase": "day",
            "lights_on": True,
            "paused": False,
            "vacation_mode": False,
            "emergency_pause": False,
        },
        "events": [
            event("info", "Aquarium established", "The biofilter and scape are ready. Add animals when you are ready to acclimate them.")
        ],
        "summary": {},
        "welfare": {"score": 100, "status": "stable", "issues": [], "animal_risks": {}},
    }


def tank_dimensions(gross_litres: float) -> dict[str, float]:
    litres = clamp(float(gross_litres), 12.0, 900.0)
    volume_cm3 = litres * 1000.0
    width = (volume_cm3 / 2.25) ** (1.0 / 3.0)
    length = width * 2.0
    height = width * 1.12
    return {
        "gross_litres": round(litres, 1),
        "effective_litres": round(litres * 0.84, 1),
        "length_cm": round(length, 1),
        "width_cm": round(width, 1),
        "height_cm": round(height, 1),
    }


def clear_scape(layout_seed: int = 42) -> dict[str, Any]:
    return {
        "rocks": [],
        "wood": [],
        "plants": [],
        "corals": [],
        "objects": [],
        "layout_seed": layout_seed,
    }


def clear_state(species: dict[str, dict[str, Any]], name: str = "Clear Aquarium", system: str = "freshwater", gross_litres: float = 60.0) -> dict[str, Any]:
    system = "saltwater" if system == "saltwater" else "freshwater"
    dims = tank_dimensions(gross_litres)
    state = default_state(species)
    state["aquarium"].update(dims)
    state["aquarium"]["name"] = name.strip() or "Clear Aquarium"
    state["aquarium"]["aquascape_style"] = "reefscape" if system == "saltwater" else "clear"
    state["aquarium"]["scape"] = clear_scape(84 if system == "saltwater" else 42)
    state["water"].update({
        "system": system,
        "temperature_c": 25.2 if system == "saltwater" else 23.0,
        "ph": 8.1 if system == "saltwater" else 7.0,
        "salinity_ppt": 35.0 if system == "saltwater" else 0.2,
        "gh_dgh": 0.0 if system == "saltwater" else 7.0,
        "kh_dkh": 8.2 if system == "saltwater" else 4.0,
        "alkalinity_dkh": 8.2 if system == "saltwater" else 4.0,
        "calcium_mg_l": 420.0 if system == "saltwater" else 35.0,
        "oxygen_mg_l": 7.1,
        "co2_mg_l": 3.0,
        "ammonia_mg_l": 0.0,
        "nitrite_mg_l": 0.0,
        "nitrate_mg_l": 0.0,
        "phosphate_mg_l": 0.05,
        "chlorine_mg_l": 0.0,
        "chloramine_mg_l": 0.0,
        "tds_mg_l": 10200.0 if system == "saltwater" else 170.0,
        "water_level": 1.0,
        "tannins": 0.0,
        "organic_waste": 0.02,
        "turbidity": 0.02,
        "surface_film": 0.01,
        "detritus": 0.01,
    })
    state["biology"].update({
        "ammonia_bacteria": 0.06,
        "nitrite_bacteria": 0.04,
        "plant_health": 1.0,
        "algae": 0.01,
    })
    state["equipment"]["filter"] = default_filter()
    state["equipment"]["filter"]["maturity"] = 0.05
    state["equipment"]["filter"]["media"]["biological"]["maturity"] = 0.05
    state["equipment"]["filter"]["media"]["chemical"]["carbon_remaining"] = 0.0
    state["equipment"]["filter"]["media"]["chemical"]["phosphate_remover_remaining"] = 0.0
    state["planning"] = default_planning(dims["gross_litres"])
    state["source_water"] = default_source_water(system)
    state["cycle"] = default_cycle()
    state["cycle"].update({
        "stage": "new",
        "days_running": 0.0,
        "ready_for_animals": False,
        "last_ammonia_dose_mg_l": 0.0,
    })
    state["maturity"] = default_maturity(0.0)
    state["animals"] = []
    state["food"] = {"available": 0.0, "decaying": 0.0, "last_fed": now_iso()}
    state["events"] = [
        event(
            "info",
            "Clear aquarium started",
            f"{state['aquarium']['name']} is an empty {dims['gross_litres']:.0f} L {system} aquarium. Cycle and scape it before adding animals.",
        )
    ]
    state["summary"] = {}
    state["welfare"] = {"score": 100, "status": "stable", "issues": [], "animal_risks": {}}
    return state


def default_filter() -> dict[str, Any]:
    return {
        "enabled": True,
        "type": "canister",
        "health": 0.96,
        "flow": 0.78,
        "effective_flow": 0.74,
        "maturity": 0.9,
        "rated_lph": 650,
        "last_serviced": now_iso(),
        "media": {
            "mechanical": {"kind": "coarse_foam_and_floss", "condition": 0.92, "clog": 0.12},
            "biological": {"kind": "ceramic_ring", "surface_area": 1.0, "maturity": 0.9, "oxygen_access": 0.82},
            "chemical": {
                "kind": "carbon_and_phosphate_pad",
                "carbon_remaining": 0.35,
                "zeolite_remaining": 0.0,
                "phosphate_remover_remaining": 0.25,
            },
        },
        "failure_mode": "",
        "noise": 0.12,
    }


def default_planning(gross_litres: float) -> dict[str, Any]:
    return {
        "estimated_total_weight_kg": estimate_total_weight_kg(gross_litres),
        "stand_rating_kg": max(120.0, estimate_total_weight_kg(gross_litres) * 1.35),
        "dedicated_stand": True,
        "level_surface": True,
        "direct_sunlight_hours": 0.0,
        "vibration_level": 0.05,
        "room_temp_swing_c": 1.5,
        "maintenance_access_cm": 10.0,
        "near_speakers_or_doors": False,
        "risk_score": 0,
        "issues": [],
    }


def default_cycle() -> dict[str, Any]:
    return {
        "method": "fishless",
        "stage": "established",
        "days_running": 35.0,
        "ready_for_animals": True,
        "last_ammonia_dose_mg_l": 0.0,
        "last_tested": now_iso(),
    }


def default_maintenance() -> dict[str, Any]:
    stamp = now_iso()
    return {
        "last_water_change": stamp,
        "last_substrate_vacuum": stamp,
        "last_filter_service": stamp,
        "last_water_test": stamp,
        "last_algae_scrape": stamp,
        "last_plant_trim": stamp,
        "last_top_off": stamp,
        "last_skimmer_cup_empty": stamp,
        "water_conditioner_used": True,
        "last_conditioner_dose": 1.0,
        "last_filter_overcleaned": False,
        "weekly_water_change_fraction": 0.25,
        "days_between_water_changes": 7,
        "days_between_filter_service": 30,
        "issues": [],
    }


def default_source_water(system: str = "freshwater") -> dict[str, Any]:
    if system == "saltwater":
        return {
            "kind": "mixed saltwater",
            "temperature_c": 25.0,
            "ph": 8.1,
            "gh_dgh": 0.0,
            "kh_dkh": 8.2,
            "tds_mg_l": 10200.0,
            "salinity_ppt": 35.0,
            "chlorine_mg_l": 0.0,
            "chloramine_mg_l": 0.0,
            "nitrate_mg_l": 0.0,
            "phosphate_mg_l": 0.02,
            "conditioner_strength": 1.0,
        }
    return {
        "kind": "conditioned tap",
        "temperature_c": 23.0,
        "ph": 7.2,
        "gh_dgh": 7.0,
        "kh_dkh": 4.0,
        "tds_mg_l": 180.0,
        "salinity_ppt": 0.2,
        "chlorine_mg_l": 0.18,
        "chloramine_mg_l": 0.08,
        "nitrate_mg_l": 4.0,
        "phosphate_mg_l": 0.08,
        "conditioner_strength": 1.0,
    }


def default_maturity(days_running: float = 0.0) -> dict[str, Any]:
    seasoning = clamp(days_running / 180.0, 0.0, 1.0)
    return {
        "biofilm": clamp(0.08 + seasoning * 0.72, 0.0, 1.0),
        "mulm": clamp(0.04 + seasoning * 0.28, 0.0, 1.0),
        "microfauna": clamp(0.03 + seasoning * 0.62, 0.0, 1.0),
        "glass_algae": clamp(0.02 + seasoning * 0.12, 0.0, 1.0),
        "plant_rooting": clamp(0.12 + seasoning * 0.65, 0.0, 1.0),
        "old_tank_risk": 0.0,
        "seasoning": seasoning,
        "last_disturbance": "",
        "last_water_change_shock": 0.0,
    }


def default_randomness() -> dict[str, Any]:
    return {
        "seed": random.SystemRandom().randint(10_000, 2_000_000_000),
        "event_index": 0,
        "noise": 0.12,
        "latest": "No recent ecosystem surprises.",
        "latest_at": "",
    }


def estimate_total_weight_kg(gross_litres: float) -> float:
    return round(gross_litres + max(8.0, gross_litres * 0.12) + max(6.0, gross_litres * 0.10), 1)


def days_since(value: str, fallback: float = 0.0) -> float:
    try:
        return max(0.0, (datetime.now() - datetime.fromisoformat(str(value))).total_seconds() / 86400.0)
    except (TypeError, ValueError):
        return fallback


def make_animal(spec: dict[str, Any], name: str, seed: int) -> dict[str, Any]:
    rng = random.Random(seed + 182)
    return {
        "id": uuid.uuid4().hex[:12],
        "species_id": spec["id"],
        "name": name,
        "sex": "female" if rng.random() > 0.5 else "male",
        "age_days": rng.randint(120, 600),
        "size_cm": spec["adult_cm"] * rng.uniform(0.72, 0.98),
        "energy": rng.uniform(0.78, 0.96),
        "hunger": rng.uniform(0.08, 0.25),
        "acute_stress": rng.uniform(0.01, 0.06),
        "chronic_stress": rng.uniform(0.01, 0.05),
        "health": rng.uniform(0.91, 0.99),
        "immune_condition": rng.uniform(0.86, 0.98),
        "genetic_resilience": rng.uniform(0.82, 1.18),
        "stress_sensitivity": rng.uniform(0.84, 1.24),
        "disease_resistance": rng.uniform(0.76, 1.2),
        "appetite_bias": rng.uniform(0.72, 1.28),
        "boldness": rng.uniform(0.18, 0.92),
        "curiosity": rng.uniform(0.12, 0.94),
        "sociability": rng.uniform(0.35, 1.0) if "school" in str(spec.get("social", "")) or "shoal" in str(spec.get("social", "")) else rng.uniform(0.08, 0.72),
        "fear_memory": 0.0,
        "microbiome_stability": rng.uniform(0.72, 1.0),
        "latent_pathogen_load": rng.uniform(0.0, 0.08),
        "feeding_rank": rng.uniform(0.2, 1.0),
        "territory_claim": rng.uniform(0.05, 0.45),
        "breeding_condition": rng.uniform(0.0, 0.18),
        "spawn_cooldown_days": rng.uniform(12, 45),
        "circadian_offset": rng.uniform(-1.5, 1.5),
        "home_x": rng.uniform(0.12, 0.88),
        "home_y": rng.uniform(0.18, 0.82),
        "sleep_x": rng.uniform(0.10, 0.90),
        "sleep_y": rng.uniform(0.58, 0.86) if spec.get("swim_zone") == "bottom" else rng.uniform(0.22, 0.72),
        "routine": "explore",
        "social_satisfaction": 1.0,
        "injury": 0.0,
        "disease": "",
        "behavior": "exploring",
        "alive": True,
        "acclimated": True,
        "acclimation_minutes": spec.get("acclimation_minutes", 30),
        "cause_of_death": "",
        "decomposition_hours": 0.0,
        "death_load_remaining": 0.0,
        "position_seed": seed,
        "last_random_event": "",
    }


def legacy_preplaced_animals(animals: list[dict[str, Any]]) -> bool:
    living = [animal for animal in animals if animal.get("alive", True)]
    if len(living) == 24:
        counts: dict[str, int] = {}
        for animal in living:
            counts[animal.get("species_id", "")] = counts.get(animal.get("species_id", ""), 0) + 1
        names = {str(animal.get("name", "")) for animal in living}
        return counts == {"neon_tetra": 8, "peppered_cory": 6, "cherry_shrimp": 10} and all(
            name.startswith(("Neon ", "Cory ", "Shrimp ")) for name in names
        )
    if len(living) == 3:
        counts = {}
        for animal in living:
            counts[animal.get("species_id", "")] = counts.get(animal.get("species_id", ""), 0) + 1
        names = {str(animal.get("name", "")) for animal in living}
        return counts == {"ocellaris_clownfish": 2, "royal_gramma": 1} and names == {"Clown 1", "Clown 2", "Gramma 1"}
    return False


def default_scape() -> dict[str, Any]:
    return {
        "rocks": [
            {"type": "river_stone", "quantity": 5, "scale": 1.0},
            {"type": "moss_stone", "quantity": 2, "scale": 0.8},
        ],
        "wood": [
            {"type": "branch_driftwood", "quantity": 2, "scale": 1.0},
            {"type": "root_driftwood", "quantity": 1, "scale": 0.9},
        ],
        "plants": [
            {"type": "dwarf_hairgrass", "quantity": 18, "health": 0.94},
            {"type": "java_fern", "quantity": 5, "health": 0.92},
            {"type": "anubias", "quantity": 4, "health": 0.9},
            {"type": "vallisneria", "quantity": 8, "health": 0.91},
            {"type": "red_root_floaters", "quantity": 6, "health": 0.88},
        ],
        "corals": [],
        "objects": [],
        "layout_seed": 42,
    }


def default_reef_scape() -> dict[str, Any]:
    return {
        "rocks": [
            {"type": "live_rock", "quantity": 7, "scale": 1.0},
            {"type": "reef_arch", "quantity": 2, "scale": 0.9},
        ],
        "wood": [],
        "plants": [
            {"type": "halimeda_macroalgae", "quantity": 5, "health": 0.84},
            {"type": "turtle_grass", "quantity": 4, "health": 0.82},
        ],
        "corals": [
            {"type": "zoanthids", "quantity": 4, "health": 0.82},
            {"type": "mushroom_coral", "quantity": 3, "health": 0.86},
            {"type": "green_star_polyps", "quantity": 2, "health": 0.8},
        ],
        "objects": [],
        "layout_seed": 84,
    }


def event(severity: str, title: str, details: str, subject: str = "") -> dict[str, Any]:
    return {
        "id": uuid.uuid4().hex[:10],
        "timestamp": now_iso(),
        "severity": severity,
        "title": title,
        "details": details,
        "subject": subject,
    }


class AquariumSimulation:
    def __init__(self, species: dict[str, dict[str, Any]], state: dict[str, Any]) -> None:
        self.species = species
        self.state = state
        self._normalize_state()
        self._event_keys: dict[str, float] = {}

    def _normalize_state(self) -> None:
        aquarium = self.state.setdefault("aquarium", {})
        aquarium.setdefault("aquascape_style", "greenscape")
        aquarium.setdefault("scape", default_scape())
        aquarium.setdefault("substrate_depth_cm", 5.0)
        water = self.state.setdefault("water", {})
        water.setdefault("system", "saltwater" if water.get("salinity_ppt", 0) > 5 else "freshwater")
        water.setdefault("salinity_ppt", 35.0 if water["system"] == "saltwater" else 0.2)
        water.setdefault("calcium_mg_l", 420.0 if water["system"] == "saltwater" else 35.0)
        water.setdefault("alkalinity_dkh", 8.2 if water["system"] == "saltwater" else water.get("kh_dkh", 4.0))
        water.setdefault("chlorine_mg_l", 0.0)
        water.setdefault("chloramine_mg_l", 0.0)
        water.setdefault("co2_mg_l", 4.0)
        water.setdefault("tds_mg_l", 10200.0 if water["system"] == "saltwater" else 180.0)
        water.setdefault("water_level", 1.0)
        water.setdefault("phosphate_mg_l", 0.35)
        water.setdefault("tannins", 0.08)
        water.setdefault("surface_film", 0.0)
        water.setdefault("detritus", 0.0)
        scape = aquarium["scape"]
        scape.setdefault("rocks", [])
        scape.setdefault("wood", [])
        scape.setdefault("plants", [])
        scape.setdefault("corals", [])
        scape.setdefault("objects", [])
        scape.setdefault("layout_seed", 42)
        equipment = self.state.setdefault("equipment", {})
        filter_state = equipment.setdefault("filter", default_filter())
        default_media = default_filter()
        filter_state.setdefault("type", default_media["type"])
        filter_state.setdefault("effective_flow", filter_state.get("flow", 0.78))
        filter_state.setdefault("rated_lph", default_media["rated_lph"])
        filter_state.setdefault("last_serviced", now_iso())
        filter_state.setdefault("failure_mode", "")
        filter_state.setdefault("noise", 0.12)
        media = filter_state.setdefault("media", {})
        for media_name, defaults in default_media["media"].items():
            existing = media.setdefault(media_name, {})
            for key, value in defaults.items():
                existing.setdefault(key, value)
        equipment.setdefault("heater", {"enabled": True, "health": 0.98, "target_c": water.get("temperature_c", 24.0), "placement_near_flow": True, "thermometer_present": True})
        equipment["heater"].setdefault("placement_near_flow", True)
        equipment["heater"].setdefault("thermometer_present", True)
        equipment["heater"].setdefault("failure_mode", "")
        equipment.setdefault("light", {"enabled": True, "health": 0.99, "hours_per_day": 8.0, "timer_enabled": True, "plant_spectrum": 0.82})
        equipment["light"].setdefault("timer_enabled", True)
        equipment["light"].setdefault("plant_spectrum", 0.82)
        equipment["light"].setdefault("start_hour", 10.0)
        equipment["light"].setdefault("failure_mode", "")
        equipment.setdefault("air_pump", {"enabled": True, "health": 0.97, "output": 0.5})
        equipment["air_pump"].setdefault("failure_mode", "")
        equipment.setdefault("protein_skimmer", {"enabled": water["system"] == "saltwater", "health": 0.95, "output": 0.55 if water["system"] == "saltwater" else 0.0, "cup_fullness": 0.0})
        equipment["protein_skimmer"].setdefault("cup_fullness", 0.0)
        equipment["protein_skimmer"].setdefault("failure_mode", "")
        equipment.setdefault("auto_top_off", {"enabled": False, "health": 0.96, "reservoir_litres": 5.0})
        equipment["auto_top_off"].setdefault("reservoir_litres", 5.0)
        equipment["auto_top_off"].setdefault("failure_mode", "")
        equipment.setdefault("checklist", default_state(self.species)["equipment"]["checklist"])
        self.state.setdefault("planning", default_planning(float(aquarium.get("gross_litres", 60.0))))
        source_defaults = default_source_water(str(water.get("system", "freshwater")))
        source = self.state.setdefault("source_water", source_defaults.copy())
        for key, value in source_defaults.items():
            source.setdefault(key, value)
        self.state.setdefault("cycle", default_cycle())
        maintenance_defaults = default_maintenance()
        maintenance = self.state.setdefault("maintenance", maintenance_defaults.copy())
        for key, value in maintenance_defaults.items():
            maintenance.setdefault(key, value)
        maturity_defaults = default_maturity(float(self.state.get("cycle", {}).get("days_running", 0.0)))
        maturity = self.state.setdefault("maturity", maturity_defaults.copy())
        for key, value in maturity_defaults.items():
            maturity.setdefault(key, value)
        randomness = self.state.setdefault("randomness", default_randomness())
        randomness.setdefault("seed", default_randomness()["seed"])
        randomness.setdefault("event_index", 0)
        randomness.setdefault("noise", 0.12)
        randomness.setdefault("latest", "No recent ecosystem surprises.")
        randomness.setdefault("latest_at", "")
        clock = self.state.setdefault("clock", {})
        clock.setdefault("simulated_at", now_iso())
        clock.setdefault("last_real_timestamp", time.time())
        clock.setdefault("total_simulated_seconds", 0.0)
        clock.setdefault("speed", 1.0)
        clock.setdefault("local_hour", datetime.now().hour + datetime.now().minute / 60.0)
        clock.setdefault("day_phase", "day")
        clock.setdefault("lights_on", False)
        clock.setdefault("paused", False)
        clock.setdefault("vacation_mode", False)
        clock.setdefault("emergency_pause", False)
        self.state.setdefault("last_test_results", {})
        self.state.setdefault("symptoms", {})
        self.state.setdefault("nursery", [])
        animals = self.state.setdefault("animals", [])
        self.state.setdefault("welfare", {"score": 100, "status": "stable", "issues": [], "animal_risks": {}})
        if legacy_preplaced_animals(animals):
            self.state["animals"] = []
            self.state.setdefault("events", []).insert(
                0,
                event("info", "Starter animals removed", "The tank now starts empty so you can choose and acclimate every animal yourself."),
            )
        for animal in self.state.get("animals", []):
            animal.setdefault("acclimated", True)
            animal.setdefault("acclimation_minutes", self.species.get(animal.get("species_id", ""), {}).get("acclimation_minutes", 30))
            animal.setdefault("decomposition_hours", 0.0)
            animal.setdefault("death_load_remaining", 0.0 if animal.get("alive", True) else self.species.get(animal.get("species_id", ""), {}).get("bioload", 0.5) * 0.1)
            animal.setdefault("genetic_resilience", 1.0)
            animal.setdefault("stress_sensitivity", 1.0)
            animal.setdefault("disease_resistance", 1.0)
            animal.setdefault("appetite_bias", 1.0)
            animal.setdefault("boldness", 0.5)
            animal.setdefault("curiosity", 0.5)
            animal.setdefault("sociability", 0.65)
            animal.setdefault("fear_memory", 0.0)
            animal.setdefault("microbiome_stability", 0.9)
            animal.setdefault("latent_pathogen_load", 0.03)
            animal.setdefault("feeding_rank", 0.6)
            animal.setdefault("territory_claim", 0.2)
            animal.setdefault("breeding_condition", 0.0)
            animal.setdefault("spawn_cooldown_days", 30.0)
            animal.setdefault("circadian_offset", 0.0)
            animal.setdefault("home_x", 0.5)
            animal.setdefault("home_y", 0.5)
            animal.setdefault("sleep_x", animal.get("home_x", 0.5))
            animal.setdefault("sleep_y", animal.get("home_y", 0.5))
            animal.setdefault("routine", "explore")
            animal.setdefault("injury", 0.0)
            animal.setdefault("last_random_event", "")
        aquarium.update(self._scape_metrics())

    def _randomness(self) -> dict[str, Any]:
        randomness = self.state.setdefault("randomness", default_randomness())
        randomness.setdefault("seed", default_randomness()["seed"])
        randomness.setdefault("event_index", 0)
        randomness.setdefault("noise", 0.12)
        randomness.setdefault("latest", "No recent ecosystem surprises.")
        randomness.setdefault("latest_at", "")
        return randomness

    def _rng(self, salt: str) -> random.Random:
        randomness = self._randomness()
        index = int(randomness.get("event_index", 0))
        randomness["event_index"] = index + 1
        return random.Random(f"{randomness.get('seed', 1)}:{index}:{salt}")

    def _noise_multiplier(self, amount: float, salt: str) -> float:
        amount = clamp(abs(amount), 0.0, 0.45)
        if amount <= 0:
            return 1.0
        return 1.0 + self._rng(salt).uniform(-amount, amount)

    def _chance(self, probability_per_hour: float, hours: float, salt: str) -> bool:
        if probability_per_hour <= 0 or hours <= 0:
            return False
        probability = 1.0 - math.exp(-probability_per_hour * hours)
        return self._rng(salt).random() < clamp(probability, 0.0, 0.98)

    def _random_note(self, title: str) -> None:
        randomness = self._randomness()
        randomness["latest"] = title
        randomness["latest_at"] = now_iso()

    def advance(self, real_seconds: float, offline: bool = False) -> None:
        clock = self.state["clock"]
        if clock["paused"] or clock["emergency_pause"]:
            clock["last_real_timestamp"] = time.time()
            return
        simulated = min(real_seconds, MAX_OFFLINE_SECONDS if offline else real_seconds) * float(clock["speed"])
        remaining = max(0.0, simulated)
        tick = 60.0 if offline else 5.0
        while remaining > 0:
            step = min(tick, remaining)
            self._tick(step)
            remaining -= step
        clock["total_simulated_seconds"] += simulated
        clock["last_real_timestamp"] = time.time()
        clock["simulated_at"] = now_iso()
        self._summarize()

    def feed(self, amount: float = 0.42) -> None:
        self.state["food"]["available"] += clamp(amount, 0.05, 1.5)
        self.state["food"]["last_fed"] = now_iso()
        self._record("info", "Aquarium fed", "Food entered the water and will be consumed according to feeding zone and hunger.")

    def water_change(
        self,
        fraction: float = 0.25,
        conditioner_used: bool = True,
        replacement_temp_c: float | None = None,
        replacement_ph: float | None = None,
        replacement_gh_dgh: float | None = None,
        disturbed_substrate: bool = False,
        conditioner_dose: float = 1.0,
    ) -> None:
        fraction = clamp(fraction, 0.05, 0.6)
        water = self.state["water"]
        source = self.state.setdefault("source_water", default_source_water(str(water.get("system", "freshwater"))))
        old_temp = float(water.get("temperature_c", 24.0))
        old_ph = float(water.get("ph", 7.0))
        old_gh = float(water.get("gh_dgh", 7.0))
        old_kh = float(water.get("kh_dkh", 4.0))
        old_tds = float(water.get("tds_mg_l", 180.0))
        replacement_temp_c = float(replacement_temp_c) if replacement_temp_c is not None else float(source.get("temperature_c", 23.0 if water.get("system") == "freshwater" else 25.0))
        replacement_ph = float(replacement_ph) if replacement_ph is not None else float(source.get("ph", old_ph))
        replacement_gh_dgh = float(replacement_gh_dgh) if replacement_gh_dgh is not None else float(source.get("gh_dgh", old_gh))
        replacement_kh = float(source.get("kh_dkh", old_kh))
        replacement_tds = float(source.get("tds_mg_l", old_tds))
        source_chlorine = float(source.get("chlorine_mg_l", 0.0))
        source_chloramine = float(source.get("chloramine_mg_l", 0.0))
        source_nitrate = float(source.get("nitrate_mg_l", 0.0))
        source_phosphate = float(source.get("phosphate_mg_l", 0.0))
        conditioner_dose = clamp(float(conditioner_dose), 0.0, 2.0)
        for key in ("ammonia_mg_l", "nitrite_mg_l", "organic_waste", "turbidity", "surface_film", "detritus"):
            water[key] *= 1.0 - fraction
        water["nitrate_mg_l"] = water["nitrate_mg_l"] * (1.0 - fraction) + source_nitrate * fraction
        water["phosphate_mg_l"] = water.get("phosphate_mg_l", 0.0) * (1.0 - fraction) + source_phosphate * fraction
        water["temperature_c"] = old_temp * (1.0 - fraction) + replacement_temp_c * fraction
        water["ph"] = clamp(old_ph * (1.0 - fraction) + replacement_ph * fraction, 4.5, 9.2)
        water["gh_dgh"] = clamp(old_gh * (1.0 - fraction) + replacement_gh_dgh * fraction, 0.0, 30.0)
        water["tds_mg_l"] = clamp(old_tds * (1.0 - fraction) + replacement_tds * fraction, 0.0, 45000.0)
        if water.get("system") == "freshwater":
            water["kh_dkh"] = clamp(old_kh * (1.0 - fraction) + max(0.2, replacement_kh) * fraction, 0.0, 20.0)
        else:
            water["salinity_ppt"] = clamp(float(water.get("salinity_ppt", 35.0)) * (1.0 - fraction) + float(source.get("salinity_ppt", 35.0)) * fraction, 0.0, 45.0)
            water["alkalinity_dkh"] = clamp(float(water.get("alkalinity_dkh", 8.2)) * (1.0 - fraction) + replacement_kh * fraction, 0.0, 16.0)
        water["oxygen_mg_l"] = clamp(water["oxygen_mg_l"] + fraction * 1.2, 0, 10)
        if conditioner_used and self.state["equipment"].get("checklist", {}).get("water_conditioner", True):
            residual = max(0.0, 1.0 - conditioner_dose * float(source.get("conditioner_strength", 1.0)))
            water["chlorine_mg_l"] = clamp(water.get("chlorine_mg_l", 0.0) * (1.0 - fraction) + source_chlorine * fraction * residual, 0, 2)
            water["chloramine_mg_l"] = clamp(water.get("chloramine_mg_l", 0.0) * (1.0 - fraction) + source_chloramine * fraction * residual, 0, 2)
        else:
            water["chlorine_mg_l"] = clamp(water.get("chlorine_mg_l", 0.0) * (1.0 - fraction) + source_chlorine * fraction, 0, 2)
            water["chloramine_mg_l"] = clamp(water.get("chloramine_mg_l", 0.0) * (1.0 - fraction) + source_chloramine * fraction, 0, 2)
        maturity = self.state.setdefault("maturity", default_maturity())
        shock = clamp(
            max(0.0, fraction - 0.35) * 0.8
            + abs(replacement_temp_c - old_temp) / 8.0
            + abs(replacement_ph - old_ph) / 1.6
            + abs(replacement_gh_dgh - old_gh) / 16.0
            + abs(replacement_kh - old_kh) / 12.0
            + abs(replacement_tds - old_tds) / (9000.0 if water.get("system") == "saltwater" else 450.0)
            + (0.18 if disturbed_substrate else 0.0)
            + (0.35 if water.get("chlorine_mg_l", 0.0) > 0.02 or water.get("chloramine_mg_l", 0.0) > 0.02 else 0.0),
            0.0,
            1.0,
        )
        maturity["last_water_change_shock"] = shock
        if disturbed_substrate:
            water["organic_waste"] = clamp(water["organic_waste"] + float(maturity.get("mulm", 0.0)) * fraction * 0.55, 0, 5)
            water["turbidity"] = clamp(water["turbidity"] + 0.12 + float(maturity.get("mulm", 0.0)) * 0.18, 0, 1)
            maturity["mulm"] = clamp(float(maturity.get("mulm", 0.0)) * (1.0 - fraction * 0.65), 0, 1)
            maturity["last_disturbance"] = "substrate disturbed during water change"
        if shock > 0.12:
            for animal in self.state.get("animals", []):
                if not animal.get("alive", True):
                    continue
                animal["acute_stress"] = clamp(float(animal.get("acute_stress", 0.0)) + shock * 0.38, 0, 1)
                animal["microbiome_stability"] = clamp(float(animal.get("microbiome_stability", 0.9)) - shock * 0.08, 0, 1)
            self.state["biology"]["ammonia_bacteria"] = clamp(self.state["biology"]["ammonia_bacteria"] * (1.0 - shock * 0.035), 0.03, 1.0)
            self.state["biology"]["nitrite_bacteria"] = clamp(self.state["biology"]["nitrite_bacteria"] * (1.0 - shock * 0.035), 0.03, 1.0)
            self._record_once("water_change_shock", "warning", "Water change caused stress", "Replacement temperature, pH, hardness, size, chlorine, or disturbed substrate created measurable shock.")
        maintenance = self.state.setdefault("maintenance", default_maintenance())
        maintenance["last_water_change"] = now_iso()
        maintenance["water_conditioner_used"] = bool(conditioner_used)
        maintenance["last_conditioner_dose"] = conditioner_dose
        self._record("info", "Partial water change", f"{fraction * 100:.0f}% changed. Shock estimate {shock * 100:.0f}% based on replacement water and disturbance.")

    def weekly_maintenance(self) -> None:
        fraction = float(self.state.get("maintenance", {}).get("weekly_water_change_fraction", 0.25))
        self.water_change(fraction, conditioner_used=True)
        water = self.state["water"]
        water["organic_waste"] = clamp(water["organic_waste"] * 0.72, 0, 5)
        water["turbidity"] = clamp(water["turbidity"] * 0.6, 0, 1)
        water["surface_film"] = clamp(water.get("surface_film", 0.0) * 0.55, 0, 1)
        water["detritus"] = clamp(water.get("detritus", 0.0) * 0.62, 0, 1)
        water["phosphate_mg_l"] = clamp(water.get("phosphate_mg_l", 0.0) * 0.9, 0, 10)
        maintenance = self.state.setdefault("maintenance", default_maintenance())
        maintenance["last_substrate_vacuum"] = now_iso()
        maintenance["last_water_test"] = now_iso()
        self._record("info", "Weekly maintenance completed", "Water was changed with conditioner, substrate waste was reduced, and parameters were checked.")

    def remove_uneaten_food(self) -> None:
        food = self.state["food"]
        water = self.state["water"]
        removed_visible = float(food.get("available", 0.0)) * 0.78
        removed_decaying = float(food.get("decaying", 0.0)) * 0.42
        food["available"] = clamp(float(food.get("available", 0.0)) - removed_visible, 0.0, 5.0)
        food["decaying"] = clamp(float(food.get("decaying", 0.0)) - removed_decaying, 0.0, 5.0)
        water["organic_waste"] = clamp(water.get("organic_waste", 0.0) * 0.92, 0, 5)
        water["surface_film"] = clamp(water.get("surface_film", 0.0) * 0.9, 0, 1)
        self._record("info", "Uneaten food removed", "Visible leftovers were siphoned out before they could mineralize into ammonia and phosphate.")

    def scrape_algae(self) -> None:
        maturity = self.state.setdefault("maturity", default_maturity())
        bio = self.state["biology"]
        water = self.state["water"]
        before = float(maturity.get("glass_algae", 0.0))
        maturity["glass_algae"] = clamp(before * 0.22, 0, 1)
        bio["algae"] = clamp(float(bio.get("algae", 0.0)) * 0.86, 0, 1)
        water["turbidity"] = clamp(water.get("turbidity", 0.0) + before * 0.06, 0, 1)
        water["organic_waste"] = clamp(water.get("organic_waste", 0.0) + before * 0.04, 0, 5)
        self.state.setdefault("maintenance", default_maintenance())["last_algae_scrape"] = now_iso()
        self._record("info", "Glass algae scraped", "Algae was removed from the glass; some loosened film entered the water column.")

    def trim_plants(self) -> None:
        scape = self.state.get("aquarium", {}).get("scape", {})
        water = self.state["water"]
        trimmed = 0.0
        for plant in scape.get("plants", []):
            quantity = float(plant.get("quantity", 1))
            if quantity > 8:
                cut = max(1.0, quantity * 0.12)
                plant["quantity"] = int(max(1.0, quantity - cut))
                plant["health"] = clamp(float(plant.get("health", 0.8)) + 0.025, 0, 1)
                trimmed += cut
        if trimmed > 0:
            water["organic_waste"] = clamp(water.get("organic_waste", 0.0) + trimmed * 0.002, 0, 5)
            self._record("info", "Plants trimmed", "Overgrown stems and leaves were trimmed, reducing shade and preventing future melt.")
        else:
            self._record("info", "Plants inspected", "No major trimming was needed.")
        self.state.setdefault("maintenance", default_maintenance())["last_plant_trim"] = now_iso()

    def top_off(self, amount: float | None = None, quiet: bool = False) -> None:
        water = self.state["water"]
        missing = clamp(1.0 - float(water.get("water_level", 1.0)), 0.0, 0.35)
        if amount is not None:
            missing = min(missing, clamp(float(amount), 0.0, 0.35))
        if missing <= 0.002:
            if not quiet:
                self._record("info", "Top-off checked", "Water level is already near full.")
            return
        old_level = max(0.55, float(water.get("water_level", 1.0)))
        new_level = clamp(old_level + missing, 0.55, 1.0)
        dilution = old_level / max(new_level, 0.55)
        water["water_level"] = new_level
        water["tds_mg_l"] = clamp(float(water.get("tds_mg_l", 180.0)) * dilution, 0, 45000)
        if water.get("system") == "saltwater":
            water["salinity_ppt"] = clamp(float(water.get("salinity_ppt", 35.0)) * dilution, 0, 45)
        water["surface_film"] = clamp(float(water.get("surface_film", 0.0)) * 0.92, 0, 1)
        self.state.setdefault("maintenance", default_maintenance())["last_top_off"] = now_iso()
        if not quiet:
            self._record("info", "Evaporation topped off", "Fresh top-off water restored level and reduced salinity/TDS concentration from evaporation.")

    def empty_skimmer_cup(self) -> None:
        skimmer = self.state["equipment"].setdefault("protein_skimmer", {"enabled": self.state["water"].get("system") == "saltwater", "health": 0.95, "output": 0.55, "cup_fullness": 0.0})
        skimmer["cup_fullness"] = 0.0
        self.state.setdefault("maintenance", default_maintenance())["last_skimmer_cup_empty"] = now_iso()
        self._record("info", "Skimmer cup emptied", "Protein skimmer export is back to normal.")

    def dose_ammonia(self, amount: float = 1.0) -> None:
        amount = clamp(amount, 0.1, 3.0)
        living = [a for a in self.state.get("animals", []) if a.get("alive", True)]
        if living:
            self._record("warning", "Ammonia dosing blocked", "Fishless cycling ammonia cannot be dosed while animals are in the tank.")
            return
        self.state["water"]["ammonia_mg_l"] = clamp(self.state["water"].get("ammonia_mg_l", 0.0) + amount, 0, 5)
        cycle = self.state.setdefault("cycle", default_cycle())
        cycle["method"] = "fishless"
        cycle["stage"] = "cycling"
        cycle["ready_for_animals"] = False
        cycle["last_ammonia_dose_mg_l"] = amount
        self._record("info", "Fishless cycle dosed", f"Added {amount:.1f} mg/L ammonia source to feed the biofilter without risking animals.")

    def test_water(self) -> None:
        self.state.setdefault("maintenance", default_maintenance())["last_water_test"] = now_iso()
        self.state.setdefault("cycle", default_cycle())["last_tested"] = now_iso()
        water = self.state["water"]
        has_kit = bool(self.state.get("equipment", {}).get("checklist", {}).get("test_kit", True))
        error = 0.06 if has_kit else 0.18
        readings = {
            "ammonia_mg_l": max(0.0, water["ammonia_mg_l"] * self._noise_multiplier(error, "test_ammonia") + self._rng("test_ammonia_floor").uniform(0.0, 0.015)),
            "nitrite_mg_l": max(0.0, water["nitrite_mg_l"] * self._noise_multiplier(error, "test_nitrite") + self._rng("test_nitrite_floor").uniform(0.0, 0.012)),
            "nitrate_mg_l": max(0.0, water["nitrate_mg_l"] * self._noise_multiplier(error * 1.15, "test_nitrate")),
            "phosphate_mg_l": max(0.0, water.get("phosphate_mg_l", 0.0) * self._noise_multiplier(error * 1.25, "test_phosphate")),
            "ph": clamp(water["ph"] + self._rng("test_ph").uniform(-0.08, 0.08) * (1.0 if has_kit else 2.0), 4.0, 10.0),
            "kh_dkh": max(0.0, water.get("kh_dkh", water.get("alkalinity_dkh", 4.0)) * self._noise_multiplier(error, "test_kh")),
            "tds_mg_l": max(0.0, water.get("tds_mg_l", 180.0) * self._noise_multiplier(error * 0.8, "test_tds")),
            "co2_mg_l": max(0.0, water.get("co2_mg_l", 4.0) * self._noise_multiplier(error * 1.4, "test_co2")),
            "chlorine_mg_l": max(0.0, (water.get("chlorine_mg_l", 0.0) + water.get("chloramine_mg_l", 0.0)) * self._noise_multiplier(error, "test_disinfectant")),
            "oxygen_mg_l": max(0.0, water["oxygen_mg_l"] * self._noise_multiplier(error * 0.65, "test_oxygen")),
            "taken_at": now_iso(),
            "confidence": "normal kit variance" if has_kit else "low confidence: no proper test kit",
        }
        self.state["last_test_results"] = readings
        self._record("info", "Water tested", f"Readings: NH3/NH4 {readings['ammonia_mg_l']:.2f}, NO2 {readings['nitrite_mg_l']:.2f}, NO3 {readings['nitrate_mg_l']:.0f}, PO4 {readings['phosphate_mg_l']:.2f}, pH {readings['ph']:.2f}, KH {readings['kh_dkh']:.1f}.")

    def service_filter(self, replace_carbon: bool = True, overclean: bool = False) -> None:
        filter_state = self.state["equipment"].setdefault("filter", default_filter())
        media = filter_state.setdefault("media", default_filter()["media"])
        mechanical = media.setdefault("mechanical", default_filter()["media"]["mechanical"].copy())
        biological = media.setdefault("biological", default_filter()["media"]["biological"].copy())
        chemical = media.setdefault("chemical", default_filter()["media"]["chemical"].copy())
        mechanical["clog"] = clamp(float(mechanical.get("clog", 0.0)) * 0.25, 0, 1)
        mechanical["condition"] = clamp(float(mechanical.get("condition", 0.8)) + 0.18, 0, 1)
        filter_state["flow"] = clamp(float(filter_state.get("flow", 0.7)) + 0.12, 0.08, 1.0)
        filter_state["health"] = clamp(float(filter_state.get("health", 0.9)) + 0.04, 0, 1)
        biological["maturity"] = clamp(float(biological.get("maturity", 0.85)) * 0.97, 0.05, 1.0)
        self.state["biology"]["ammonia_bacteria"] = clamp(self.state["biology"]["ammonia_bacteria"] * 0.985, 0.05, 1.0)
        self.state["biology"]["nitrite_bacteria"] = clamp(self.state["biology"]["nitrite_bacteria"] * 0.985, 0.05, 1.0)
        if overclean:
            biological["maturity"] = clamp(float(biological.get("maturity", 0.85)) * 0.52, 0.02, 1.0)
            self.state["biology"]["ammonia_bacteria"] = clamp(self.state["biology"]["ammonia_bacteria"] * 0.58, 0.02, 1.0)
            self.state["biology"]["nitrite_bacteria"] = clamp(self.state["biology"]["nitrite_bacteria"] * 0.55, 0.02, 1.0)
            self.state.setdefault("maturity", default_maturity())["last_disturbance"] = "filter media was over-cleaned"
            self._record("warning", "Filter was over-cleaned", "Too much biological media was disturbed; watch ammonia and nitrite for the next few days.")
        if replace_carbon:
            chemical["carbon_remaining"] = 1.0
            chemical["phosphate_remover_remaining"] = 1.0
        filter_state["last_serviced"] = now_iso()
        filter_state["failure_mode"] = ""
        filter_state["noise"] = clamp(float(filter_state.get("noise", 0.12)) * 0.55, 0.02, 1.0)
        self.state.setdefault("maintenance", default_maintenance())["last_filter_overcleaned"] = bool(overclean)
        self._record("info", "Filter serviced", "Mechanical media was rinsed gently, flow improved, carbon and phosphate-removing media were refreshed, and the biofilter was disturbed only slightly.")

    def set_equipment(self, equipment: str, enabled: bool | None = None, value: float | None = None) -> None:
        gear = self.state.setdefault("equipment", {})
        if equipment == "filter":
            filter_state = gear.setdefault("filter", default_filter())
            if enabled is not None:
                filter_state["enabled"] = bool(enabled)
            if value is not None:
                filter_state["flow"] = clamp(float(value), 0.08, 1.0)
            self._record("info", "Filter adjusted", f"Filter is {'on' if filter_state.get('enabled', True) else 'off'} at {float(filter_state.get('flow', 0.7)) * 100:.0f}% base flow.")
        elif equipment == "heater":
            heater = gear.setdefault("heater", {"enabled": True, "health": 0.98, "target_c": 24.0, "placement_near_flow": True, "thermometer_present": True})
            if enabled is not None:
                heater["enabled"] = bool(enabled)
            if value is not None:
                heater["target_c"] = clamp(float(value), 16.0, 31.0)
            self._record("info", "Heater adjusted", f"Heater is {'on' if heater.get('enabled', True) else 'off'} with target {float(heater.get('target_c', 24.0)):.1f} C.")
        elif equipment == "light":
            light = gear.setdefault("light", {"enabled": True, "health": 0.99, "hours_per_day": 8.0, "timer_enabled": True, "plant_spectrum": 0.82})
            if enabled is not None:
                light["enabled"] = bool(enabled)
            if value is not None:
                light["hours_per_day"] = clamp(float(value), 0.0, 14.0)
            self._record("info", "Lighting adjusted", f"Light is {'on' if light.get('enabled', True) else 'off'} for {float(light.get('hours_per_day', 8.0)):.1f} hours per day.")
        elif equipment == "air_pump":
            pump = gear.setdefault("air_pump", {"enabled": True, "health": 0.97, "output": 0.5})
            if enabled is not None:
                pump["enabled"] = bool(enabled)
            if value is not None:
                pump["output"] = clamp(float(value), 0.0, 1.0)
            self._record("info", "Air pump adjusted", f"Air pump is {'on' if pump.get('enabled', True) else 'off'} at {float(pump.get('output', 0.5)) * 100:.0f}% output.")
        elif equipment == "protein_skimmer":
            skimmer = gear.setdefault("protein_skimmer", {"enabled": self.state["water"].get("system") == "saltwater", "health": 0.95, "output": 0.55, "cup_fullness": 0.0})
            if enabled is not None:
                skimmer["enabled"] = bool(enabled)
            if value is not None:
                skimmer["output"] = clamp(float(value), 0.0, 1.0)
            self._record("info", "Protein skimmer adjusted", f"Skimmer is {'on' if skimmer.get('enabled', True) else 'off'} at {float(skimmer.get('output', 0.55)) * 100:.0f}% output.")
        elif equipment == "auto_top_off":
            ato = gear.setdefault("auto_top_off", {"enabled": False, "health": 0.96, "reservoir_litres": 5.0})
            if enabled is not None:
                ato["enabled"] = bool(enabled)
            if value is not None:
                ato["reservoir_litres"] = clamp(float(value), 0.0, 40.0)
            self._record("info", "Auto top-off adjusted", f"ATO is {'on' if ato.get('enabled', False) else 'off'} with {float(ato.get('reservoir_litres', 0.0)):.1f} L in the reservoir.")
        self._summarize()

    def set_substrate(self, substrate: str = "fine_sand", depth_cm: float = 5.0) -> None:
        valid = {
            "fine_sand": "fine sand",
            "rounded_gravel": "rounded gravel",
            "planted_soil": "planted soil",
            "reef_sand": "reef sand",
            "bare_bottom": "bare bottom",
        }
        if substrate not in valid:
            substrate = "fine_sand"
        depth_cm = clamp(depth_cm, 0.0, 9.0)
        if substrate == "bare_bottom":
            depth_cm = 0.0
        self.state["aquarium"]["substrate"] = substrate
        self.state["aquarium"]["substrate_depth_cm"] = depth_cm
        if substrate == "planted_soil":
            self.state["aquarium"]["maintenance_load"] = clamp(float(self.state["aquarium"].get("maintenance_load", 0.0)) + 0.03, 0, 1)
            self.state["biology"]["plant_health"] = clamp(float(self.state["biology"].get("plant_health", 1.0)) + 0.04, 0, 1)
        elif substrate == "bare_bottom":
            self.state["water"]["organic_waste"] = clamp(float(self.state["water"].get("organic_waste", 0.0)) * 0.82, 0, 5)
        self._record("info", "Substrate adjusted", f"Changed substrate to {valid[substrate]} at {depth_cm:.1f} cm depth.")
        self._summarize()

    def setup_clear_aquarium(self, name: str = "", system: str = "freshwater", gross_litres: float = 60.0) -> None:
        keep_clock = self.state.get("clock", {})
        self.state.clear()
        self.state.update(clear_state(self.species, name or "Clear Aquarium", system, gross_litres))
        self.state["clock"].update(keep_clock)
        self._normalize_state()

    def switch_system(self, system: str) -> None:
        if system not in {"freshwater", "saltwater"}:
            return
        self.state["animals"] = []
        water = self.state["water"]
        aquarium = self.state["aquarium"]
        water["system"] = system
        if system == "saltwater":
            aquarium["name"] = "Reef Room"
            aquarium["aquascape_style"] = "reefscape"
            aquarium["scape"] = default_reef_scape()
            water.update({
                "temperature_c": 25.8,
                "ph": 8.15,
                "salinity_ppt": 35.0,
                "gh_dgh": 0.0,
                "kh_dkh": 8.2,
                "alkalinity_dkh": 8.2,
                "calcium_mg_l": 420.0,
                "oxygen_mg_l": 7.2,
                "ammonia_mg_l": 0.0,
                "nitrite_mg_l": 0.0,
                "nitrate_mg_l": 5.0,
                "organic_waste": 0.08,
                "turbidity": 0.03,
                "water_level": 1.0,
            })
            self.state["source_water"] = default_source_water("saltwater")
            self.state["equipment"]["protein_skimmer"] = {"enabled": True, "health": 0.95, "output": 0.58, "cup_fullness": 0.0}
            self.state["equipment"]["auto_top_off"] = {"enabled": False, "health": 0.96, "reservoir_litres": 8.0}
            self.state["equipment"]["checklist"]["protein_skimmer"] = True
            self.state["equipment"]["checklist"]["auto_top_off"] = False
            self._record("info", "Saltwater reef started", "The tank was converted to a conservative starter reef. Add marine animals when you are ready to acclimate them.")
        else:
            fresh = default_state(self.species)
            keep_clock = self.state.get("clock", {})
            self.state.update(fresh)
            self.state["clock"].update(keep_clock)
            self._record("info", "Freshwater greenscape started", "The tank was converted back to the planted freshwater starter layout.")
        self._normalize_state()

    def add_animal(self, species_id: str, acclimation_minutes: int = 30, name: str = "") -> dict[str, Any] | None:
        if species_id not in self.species:
            return None
        spec = self.species[species_id]
        system = self.state["water"].get("system", "freshwater")
        if spec.get("water_type", "freshwater") != system:
            self._record("warning", "Wrong water system", f"{spec['common_name']} cannot be added to a {system} tank.")
            return None
        seed = int(time.time() * 1000) % 100000
        count = sum(1 for animal in self.state["animals"] if animal.get("species_id") == species_id)
        animal = make_animal(spec, name or f"{spec['common_name']} {count + 1}", seed + count)
        required = int(spec.get("acclimation_minutes", 30))
        animal["acclimation_minutes"] = int(acclimation_minutes)
        animal["acclimated"] = acclimation_minutes >= required
        if animal["acclimated"]:
            animal["acute_stress"] = clamp(animal["acute_stress"] + 0.08, 0, 1)
            animal["behavior"] = "settling into the tank"
            self._record("info", "Animal acclimated", f"{animal['name']} was added after {acclimation_minutes} minutes of acclimation.")
        else:
            shortfall = 1.0 - clamp(acclimation_minutes / max(1, required), 0, 1)
            animal["acute_stress"] = clamp(0.65 + shortfall * 0.35, 0, 1)
            animal["health"] = clamp(0.18 - shortfall * 0.16, 0, 1)
            animal["behavior"] = "acclimation shock"
            self._record("critical", "Acclimation skipped", f"{animal['name']} was added without enough acclimation. Severe osmotic shock is likely.")
            if acclimation_minutes < required * 0.25:
                animal["alive"] = False
                animal["cause_of_death"] = "Primary cause: acclimation shock. The animal was moved before temperature and water chemistry could equalize."
                self._apply_death_load(animal, immediate=True)
                self._record("critical", f"{animal['name']} died", animal["cause_of_death"], animal["id"])
        self.state["animals"].append(animal)
        self._summarize()
        return animal

    def remove_animal(self, animal_id: str = "") -> None:
        animals = self.state.get("animals", [])
        if animal_id:
            remaining = [animal for animal in animals if animal.get("id") != animal_id]
            removed = len(remaining) != len(animals)
            self.state["animals"] = remaining
        else:
            removed = bool(animals)
            if animals:
                animals.pop()
        if removed:
            self._record("info", "Animal transferred out", "The selected animal was removed from the aquarium without force or cleanup side effects.")
        self._summarize()

    def place_scape_item(self, category: str, item_type: str, x: float, y: float, scale: float = 1.0) -> None:
        category = "wood" if category == "log" else category
        if not self._is_scape_item_allowed(category, item_type):
            return
        valid, reason, x, y = self._validated_position(category, item_type, x, y)
        if not valid:
            self._record("warning", "Invalid scape placement", reason)
            return
        scape = self.state["aquarium"]["scape"]
        obj = {
            "id": uuid.uuid4().hex[:10],
            "category": category,
            "type": item_type,
            "x": x,
            "y": y,
            "scale": clamp(scale, 0.45, 1.8),
            "health": 0.86 if category in {"plants", "corals"} else 1.0,
        }
        scape.setdefault("objects", []).append(obj)
        self.state["aquarium"].update(self._scape_metrics())
        self._record("info", "Scape placed", f"{item_type.replace('_', ' ')} was placed in the aquarium.")

    def move_scape_item(self, object_id: str, x: float, y: float) -> None:
        for obj in self.state["aquarium"]["scape"].setdefault("objects", []):
            if obj.get("id") != object_id:
                continue
            valid, reason, x, y = self._validated_position(str(obj.get("category", "")), str(obj.get("type", "")), x, y)
            if not valid:
                self._record("warning", "Invalid scape relocation", reason)
                return
            obj["x"], obj["y"] = x, y
            self.state["aquarium"].update(self._scape_metrics())
            self._record("info", "Scape moved", f"{str(obj.get('type', 'scape item')).replace('_', ' ')} was relocated.")
            return

    def remove_scape_item(self, object_id: str) -> None:
        objects = self.state["aquarium"]["scape"].setdefault("objects", [])
        before = len(objects)
        self.state["aquarium"]["scape"]["objects"] = [obj for obj in objects if obj.get("id") != object_id]
        self.state["aquarium"].update(self._scape_metrics())
        if len(self.state["aquarium"]["scape"]["objects"]) != before:
            self._record("info", "Scape removed", "The selected scape object was removed.")

    def _is_scape_item_allowed(self, category: str, item_type: str) -> bool:
        system = self.state["water"].get("system", "freshwater")
        catalogue = {"plants": PLANT_TYPES, "rocks": HARDSCAPE_TYPES, "wood": HARDSCAPE_TYPES, "corals": CORAL_TYPES}.get(category, {})
        if item_type not in catalogue:
            return False
        needed = catalogue[item_type].get("system")
        if category == "corals":
            needed = "saltwater"
        if needed and needed != system:
            self._record("warning", "Wrong scape system", f"{catalogue[item_type]['name']} belongs in a {needed} aquarium.")
            return False
        return True

    def _validated_position(self, category: str, item_type: str, x: float, y: float) -> tuple[bool, str, float, float]:
        x = clamp(float(x), 0.03, 0.97)
        y = clamp(float(y), 0.05, 0.95)
        if category == "plants" and item_type == "red_root_floaters":
            if y > 0.22:
                return False, "Floating plants must stay near the water surface.", x, y
            return True, "", x, y
        if category == "plants" and item_type == "hornwort":
            if 0.25 < y < 0.70:
                return False, "Hornwort must either float near the surface or be planted into the substrate.", x, y
            return True, "", x, y
        if category == "plants" and y < 0.70:
            return False, "Rooted plants cannot be placed in open water.", x, y
        if category in {"rocks", "wood", "corals"} and y < 0.52:
            return False, "Hardscape and corals need a surface, not open air or midwater.", x, y
        return True, "", x, y

    def reset_scape(self) -> None:
        if self.state["water"].get("system") == "saltwater":
            self.state["aquarium"]["scape"] = default_reef_scape()
            title = "Reefscape restored"
            details = "The saltwater scape was reset to a conservative starter reef."
        else:
            self.state["aquarium"]["scape"] = default_scape()
            title = "Greenscape restored"
            details = "The aquascape was reset to the balanced planted starter layout."
        self.state["aquarium"].update(self._scape_metrics())
        self._record("info", title, details)

    def clear_scape(self) -> None:
        self.state["aquarium"]["scape"] = clear_scape(84 if self.state["water"].get("system") == "saltwater" else 42)
        self.state["aquarium"]["aquascape_style"] = "clear"
        self.state["aquarium"].update(self._scape_metrics())
        self._record("info", "Scape cleared", "The aquarium is now visually empty except for water, substrate, equipment, and any animals.")

    def add_scape_item(self, category: str, item_type: str, quantity: int = 1) -> None:
        category = "wood" if category == "log" else category
        if category not in {"rocks", "wood", "plants"}:
            return
        catalogue = PLANT_TYPES if category == "plants" else HARDSCAPE_TYPES
        if item_type not in catalogue:
            return
        quantity = int(clamp(quantity, 1, 8))
        scape = self.state["aquarium"]["scape"]
        items = scape.setdefault(category, [])
        for item in items:
            if item.get("type") == item_type:
                item["quantity"] = int(item.get("quantity", 0)) + quantity
                if category == "plants":
                    item["health"] = max(float(item.get("health", 0.8)), 0.82)
                break
        else:
            item = {"type": item_type, "quantity": quantity, "scale": 1.0}
            if category == "plants":
                item["health"] = 0.86
            items.append(item)
        self.state["aquarium"].update(self._scape_metrics())
        name = catalogue[item_type]["name"]
        self._record("info", "Aquascape changed", f"Added {quantity} x {name}.")

    def _scape_metrics(self) -> dict[str, float]:
        scape = self.state.get("aquarium", {}).get("scape", default_scape())
        nitrate_uptake = 0.0
        oxygen_day = 0.0
        oxygen_night = 0.0
        hiding = 0.0
        algae_control = 0.0
        maintenance = 0.0
        surface_shade = 0.0
        soft_water = 0.0
        flow_break = 0.0
        for plant in self._expanded_scape_items("plants"):
            data = PLANT_TYPES.get(plant.get("type", ""), {})
            quantity = float(plant.get("quantity", 0))
            health = float(plant.get("health", 0.75))
            weight = quantity * health
            nitrate_uptake += data.get("nitrate_uptake", 0.0) * weight
            oxygen_day += data.get("oxygen_day", 0.0) * weight
            oxygen_night += data.get("oxygen_night", 0.0) * weight
            hiding += data.get("hiding", 0.0) * weight
            algae_control += data.get("algae_control", 0.0) * weight
            maintenance += data.get("maintenance", 0.0) * quantity * (1.15 - health)
            surface_shade += data.get("surface_shade", 0.0) * weight
        for coral in self._expanded_scape_items("corals"):
            data = CORAL_TYPES.get(coral.get("type", ""), {})
            quantity = float(coral.get("quantity", 0))
            health = float(coral.get("health", 0.75))
            weight = quantity * health
            nitrate_uptake += data.get("nitrate_uptake", 0.0) * weight
            hiding += data.get("hiding", 0.0) * weight
            algae_control += data.get("algae_control", 0.0) * weight
            maintenance += data.get("maintenance", 0.0) * quantity * (1.15 - health)
        for category in ("rocks", "wood"):
            for item in self._expanded_scape_items(category):
                data = HARDSCAPE_TYPES.get(item.get("type", ""), {})
                weight = float(item.get("quantity", 0)) * float(item.get("scale", 1.0))
                hiding += data.get("hiding", 0.0) * weight
                algae_control += data.get("algae_control", 0.0) * weight
                nitrate_uptake += data.get("biofilter", 0.0) * weight
                soft_water += data.get("soft_water", 0.0) * weight
                flow_break += data.get("flow_break", 0.0) * weight
        return {
            "plant_cover": clamp(nitrate_uptake / 4.2, 0.05, 0.96),
            "hiding_cover": clamp(hiding / 3.6, 0.05, 0.96),
            "nitrate_uptake": clamp(nitrate_uptake / 5.0, 0.02, 1.3),
            "oxygen_day": clamp(oxygen_day / 5.0, 0.0, 0.9),
            "oxygen_night": clamp(oxygen_night / 5.0, -0.5, 0.0),
            "algae_control": clamp(algae_control / 2.8, 0.0, 0.85),
            "maintenance_load": clamp(maintenance / 2.5, 0.0, 0.55),
            "surface_shade": clamp(surface_shade / 2.0, 0.0, 0.65),
            "soft_water": clamp(soft_water, 0.0, 0.35),
            "flow_break": clamp(flow_break, 0.0, 0.35),
        }

    def _expanded_scape_items(self, category: str) -> list[dict[str, Any]]:
        scape = self.state.get("aquarium", {}).get("scape", {})
        items = [dict(item) for item in scape.get(category, [])]
        for obj in scape.get("objects", []):
            if obj.get("category") == category:
                item = dict(obj)
                item["quantity"] = 1
                items.append(item)
        return items

    def _groups(self, living: list[dict[str, Any]]) -> dict[str, int]:
        groups: dict[str, int] = {}
        for animal in living:
            groups[animal["species_id"]] = groups.get(animal["species_id"], 0) + 1
        return groups

    def _evaluate_planning(self) -> dict[str, Any]:
        planning = self.state.setdefault("planning", default_planning(float(self.state["aquarium"].get("gross_litres", 60.0))))
        litres = float(self.state["aquarium"].get("gross_litres", 60.0))
        weight = estimate_total_weight_kg(litres)
        planning["estimated_total_weight_kg"] = weight
        issues: list[dict[str, Any]] = []
        stand_rating = float(planning.get("stand_rating_kg", 0.0))
        if stand_rating < weight * 1.15 or not planning.get("dedicated_stand", False):
            issues.append({"severity": "critical", "title": "Stand may be unsafe", "details": f"Estimated system weight is {weight:.0f} kg. Use a level aquarium stand rated above the full loaded weight."})
        if not planning.get("level_surface", True):
            issues.append({"severity": "critical", "title": "Tank is not level", "details": "Uneven support can twist glass seams and stress the aquarium."})
        sunlight = float(planning.get("direct_sunlight_hours", 0.0))
        if sunlight > 0.5:
            issues.append({"severity": "warning", "title": "Direct sunlight risk", "details": f"{sunlight:.1f} hours of direct sun can cause algae and temperature swings."})
        if float(planning.get("vibration_level", 0.0)) > 0.45 or planning.get("near_speakers_or_doors", False):
            issues.append({"severity": "warning", "title": "Vibration stress", "details": "Doors, speakers, and repeated vibration stress fish and can disturb hardscape."})
        if float(planning.get("room_temp_swing_c", 0.0)) > 4.0:
            issues.append({"severity": "warning", "title": "Room temperature swings", "details": "Large room swings make heater stability harder and can stress animals."})
        if float(planning.get("maintenance_access_cm", 0.0)) < 6.0:
            issues.append({"severity": "warning", "title": "Maintenance access is tight", "details": "Leave space behind and above the aquarium for siphons, cables, filter hoses, and safe cleaning."})
        planning["issues"] = issues
        planning["risk_score"] = min(100, sum(45 if i["severity"] == "critical" else 18 for i in issues))
        return planning

    def _update_cycle(self, hours: float) -> dict[str, Any]:
        cycle = self.state.setdefault("cycle", default_cycle())
        cycle["days_running"] = float(cycle.get("days_running", 0.0)) + hours / 24.0
        water = self.state["water"]
        ready = (
            water["ammonia_mg_l"] <= 0.05
            and water["nitrite_mg_l"] <= 0.05
            and self.state["biology"]["ammonia_bacteria"] >= 0.72
            and self.state["biology"]["nitrite_bacteria"] >= 0.72
        )
        if ready:
            cycle["stage"] = "established" if cycle["days_running"] >= 21 else "seeded"
            cycle["ready_for_animals"] = True
        else:
            cycle["stage"] = "cycling"
            cycle["ready_for_animals"] = False
        return cycle

    def _maintenance_status(self) -> dict[str, Any]:
        maintenance = self.state.setdefault("maintenance", default_maintenance())
        issues: list[dict[str, Any]] = []
        water_days = days_since(maintenance.get("last_water_change", ""), 999)
        filter_days = days_since(maintenance.get("last_filter_service", ""), 999)
        test_days = days_since(maintenance.get("last_water_test", ""), 999)
        scrape_days = days_since(maintenance.get("last_algae_scrape", ""), 999)
        trim_days = days_since(maintenance.get("last_plant_trim", ""), 999)
        water = self.state["water"]
        symptoms = self.state.get("symptoms", {})
        if water_days > float(maintenance.get("days_between_water_changes", 7)) + 3:
            issues.append({"severity": "warning", "title": "Water change overdue", "details": f"Last water change was {water_days:.0f} days ago."})
        if filter_days > float(maintenance.get("days_between_filter_service", 30)) + 10:
            issues.append({"severity": "warning", "title": "Filter service overdue", "details": f"Last filter service was {filter_days:.0f} days ago. Rinse mechanical media in tank water."})
        if test_days > 7 or water["ammonia_mg_l"] > 0.05 or water["nitrite_mg_l"] > 0.05:
            issues.append({"severity": "warning", "title": "Water test needed", "details": "Test ammonia, nitrite, nitrate, phosphate, pH, KH, and temperature before adding animals or after any spike."})
        if scrape_days > 14 and float(symptoms.get("glass_algae", self.state.get("maturity", {}).get("glass_algae", 0.0))) > 0.35:
            issues.append({"severity": "warning", "title": "Glass algae needs scraping", "details": "Visible algae is shading the view and feeding a larger algae cycle."})
        if trim_days > 21 and self.state["aquarium"].get("surface_shade", 0.0) > 0.45:
            issues.append({"severity": "warning", "title": "Plants need trimming", "details": "Overgrown or floating plants are shading lower growth and can melt back."})
        if water.get("surface_film", 0.0) > 0.45:
            issues.append({"severity": "warning", "title": "Surface film needs removal", "details": "Skim or disturb the surface to restore gas exchange."})
        if water.get("detritus", 0.0) > 0.58:
            issues.append({"severity": "warning", "title": "Substrate debris is high", "details": "Gentle vacuuming will reduce long-term nitrate and phosphate pressure."})
        if water.get("water_level", 1.0) < 0.95:
            issues.append({"severity": "warning", "title": "Top-off needed", "details": "Evaporation lowered the water level and concentrated dissolved minerals."})
        skimmer = self.state.get("equipment", {}).get("protein_skimmer", {})
        if water.get("system") == "saltwater" and bool(skimmer.get("enabled", False)) and float(skimmer.get("cup_fullness", 0.0)) > 0.75:
            issues.append({"severity": "warning", "title": "Skimmer cup filling", "details": "Empty the collection cup before export efficiency drops."})
        maintenance["issues"] = issues
        return maintenance

    def _time_context(self) -> dict[str, Any]:
        light = self.state["equipment"]["light"]
        hours_per_day = clamp(float(light.get("hours_per_day", 8.0)), 0, 16)
        hour = datetime.now().hour + datetime.now().minute / 60.0
        start = clamp(float(light.get("start_hour", 10.0)), 0.0, 23.75)
        end = (start + hours_per_day) % 24.0
        if hours_per_day <= 0.0 or not bool(light.get("enabled", True)):
            lights_on = False
        elif start + hours_per_day <= 24.0:
            lights_on = start <= hour < start + hours_per_day
        else:
            lights_on = hour >= start or hour < end
        phase = "night"
        if lights_on:
            phase = "day"
        elif 5.5 <= hour < 8.0:
            phase = "dawn"
        elif 18.0 <= hour < 21.0:
            phase = "dusk"
        clock = self.state.setdefault("clock", {})
        clock["local_hour"] = round(hour, 2)
        clock["day_phase"] = phase
        clock["lights_on"] = lights_on
        return {"lights_on": lights_on, "light_hours": hours_per_day, "local_hour": hour, "day_phase": phase}

    def _lighting_window(self) -> tuple[bool, float]:
        context = self._time_context()
        return bool(context["lights_on"]), float(context["light_hours"])

    def _add_animal_risk(self, animal_risks: dict[str, dict[str, Any]], animal: dict[str, Any], stress: float, damage_per_hour: float, reason: str) -> None:
        risk = animal_risks.setdefault(animal["id"], {"stress": 0.0, "damage_per_hour": 0.0, "injury_per_hour": 0.0, "reasons": []})
        risk["stress"] = max(float(risk["stress"]), clamp(stress, 0.0, 1.0))
        risk["damage_per_hour"] = float(risk["damage_per_hour"]) + max(0.0, damage_per_hour)
        if reason and reason not in risk["reasons"]:
            risk["reasons"].append(reason)

    def _add_injury_risk(self, animal_risks: dict[str, dict[str, Any]], animal: dict[str, Any], injury_per_hour: float, reason: str) -> None:
        risk = animal_risks.setdefault(animal["id"], {"stress": 0.0, "damage_per_hour": 0.0, "injury_per_hour": 0.0, "reasons": []})
        risk["injury_per_hour"] = float(risk.get("injury_per_hour", 0.0)) + max(0.0, injury_per_hour)
        if reason and reason not in risk["reasons"]:
            risk["reasons"].append(reason)

    def _community_welfare(self, living: list[dict[str, Any]], groups: dict[str, int]) -> dict[str, Any]:
        aquarium = self.state["aquarium"]
        animal_risks: dict[str, dict[str, Any]] = {}
        issues: list[dict[str, Any]] = []
        if not living:
            return {"score": 100, "status": "stable", "issues": [], "animal_risks": {}}

        litres = max(1.0, float(aquarium.get("effective_litres", 1.0)))
        active_load = sum(
            self.species[a["species_id"]].get("bioload", 0.5) * (0.75 + self.species[a["species_id"]].get("activity", 0.5) * 0.65)
            for a in living
        )
        stocking_pressure = active_load / max(1.0, litres / 8.0)
        if stocking_pressure > 1.0:
            severity = clamp((stocking_pressure - 1.0) / 0.75, 0.0, 1.0)
            issues.append({
                "key": "overstocking",
                "severity": "critical" if severity > 0.65 else "warning",
                "title": "The tank is overstocked",
                "details": f"Active bioload is {stocking_pressure:.1f}x the conservative capacity for this volume. Reduce stocking or improve volume/filtration.",
            })
            for animal in living:
                self._add_animal_risk(animal_risks, animal, 0.3 + severity * 0.35, severity * 0.006, "crowding and waste pressure")

        hiding = float(aquarium.get("hiding_cover", 0.0))
        open_swimming = float(aquarium.get("open_swimming", 0.55))
        filter_state = self.state.get("equipment", {}).get("filter", {})
        current_strength = float(filter_state.get("effective_flow", filter_state.get("flow", 0.6)))
        planning = self._evaluate_planning()
        cycle = self.state.setdefault("cycle", default_cycle())
        checklist = self.state.get("equipment", {}).get("checklist", {})
        heater = self.state.get("equipment", {}).get("heater", {})
        water = self.state["water"]
        if not cycle.get("ready_for_animals", False):
            issues.append({
                "key": "uncycled_tank",
                "severity": "critical",
                "title": "Tank is not cycled",
                "details": "Ammonia and nitrite must return to zero with a mature biofilter before animals are safe.",
            })
            for animal in living:
                self._add_animal_risk(animal_risks, animal, 0.72, 0.018, "uncycled aquarium")
        disinfectant = float(water.get("chlorine_mg_l", 0.0)) + float(water.get("chloramine_mg_l", 0.0)) * 1.25
        if disinfectant > 0.02:
            issues.append({
                "key": "chlorine",
                "severity": "critical",
                "title": "Untreated tap water detected",
                "details": "Chlorine or chloramine exposure can burn gills and damage biofilter bacteria.",
            })
            for animal in living:
                self._add_animal_risk(animal_risks, animal, 0.9, 0.06, "untreated tap water")
        if water.get("co2_mg_l", 0.0) > 18.0:
            severity = clamp((float(water.get("co2_mg_l", 0.0)) - 18.0) / 18.0, 0.0, 1.0)
            issues.append({
                "key": "high_co2",
                "severity": "critical" if severity > 0.55 else "warning",
                "title": "CO2 is crowding oxygen",
                "details": "High dissolved CO2 can make fish breathe hard even before oxygen reads critically low.",
            })
            for animal in living:
                self._add_animal_risk(animal_risks, animal, 0.22 + severity * 0.45, severity * 0.012, "high dissolved CO2")
        if water.get("surface_film", 0.0) > 0.45:
            severity = clamp((float(water.get("surface_film", 0.0)) - 0.45) / 0.45, 0.0, 1.0)
            issues.append({
                "key": "surface_film",
                "severity": "warning",
                "title": "Surface film is limiting gas exchange",
                "details": "Protein/oil film is reducing oxygen exchange at the surface.",
            })
            for animal in living:
                self._add_animal_risk(animal_risks, animal, 0.12 + severity * 0.22, severity * 0.002, "surface film reduced gas exchange")
        for issue in planning.get("issues", []):
            if issue["severity"] == "critical":
                issues.append({"key": "planning_" + issue["title"].lower().replace(" ", "_"), **issue})
        missing_required = [name for name in ("filter", "heater", "thermometer", "water_conditioner", "test_kit", "siphon") if not checklist.get(name, True)]
        if missing_required:
            issues.append({
                "key": "missing_equipment",
                "severity": "warning",
                "title": "Required equipment missing",
                "details": "Missing: " + ", ".join(missing_required) + ".",
            })
        if not heater.get("placement_near_flow", True):
            issues.append({
                "key": "heater_placement",
                "severity": "warning",
                "title": "Heater placement is weak",
                "details": "Heaters placed away from flow can create uneven warm/cold zones.",
            })
            for animal in living:
                self._add_animal_risk(animal_risks, animal, 0.18, 0.0008, "temperature gradient")
        territorial_pressure = sum(self.species[a["species_id"]].get("territoriality", 0.0) for a in living) / max(1.0, hiding * 12.0)
        if territorial_pressure > 0.55:
            severity = clamp((territorial_pressure - 0.55) / 0.9, 0.0, 1.0)
            issues.append({
                "key": "aggression",
                "severity": "critical" if severity > 0.7 else "warning",
                "title": "Aggression pressure is high",
                "details": "Territorial fish need more space, broken sight lines, and hiding cover.",
            })
            for animal in living:
                self._add_animal_risk(animal_risks, animal, 0.25 + severity * 0.35, severity * 0.004, "territorial aggression pressure")

        for species_id, count in groups.items():
            spec = self.species[species_id]
            minimum = int(spec.get("minimum_group", 1))
            preferred = int(spec.get("preferred_group", minimum))
            social = str(spec.get("social", ""))
            members = [a for a in living if a["species_id"] == species_id]
            if minimum > 1 and count < minimum:
                missing_ratio = (minimum - count) / max(1, minimum)
                hard_social = any(word in social for word in ("school", "shoal", "colony", "group"))
                stress = (0.55 if hard_social else 0.35) + missing_ratio * (0.45 if hard_social else 0.3)
                damage = missing_ratio * (0.012 if hard_social else 0.004)
                if hard_social and count == 1:
                    damage += 0.012
                common_name = spec.get("common_name", species_id)
                issues.append({
                    "key": f"group_{species_id}",
                    "severity": "critical" if hard_social and missing_ratio > 0.45 else "warning",
                    "title": f"{common_name} needs a group",
                    "details": f"{common_name} has {count}; this species needs at least {minimum} and does best around {preferred}.",
                })
                for animal in members:
                    self._add_animal_risk(animal_risks, animal, stress, damage, f"undersized {common_name} group")
            elif preferred > minimum and count < preferred:
                for animal in members:
                    self._add_animal_risk(animal_risks, animal, 0.16, 0.0, "below preferred group size")

            if preferred <= 2 and spec.get("territoriality", 0.0) > 0.3 and count > preferred:
                severity = clamp((count - preferred) / max(1, preferred + 1), 0.0, 1.0)
                issues.append({
                    "key": f"same_species_aggression_{species_id}",
                    "severity": "critical" if severity > 0.65 else "warning",
                    "title": f"{spec.get('common_name', species_id)} may fight",
                    "details": f"This territorial species is above its preferred group size of {preferred}.",
                })
                for animal in members:
                    self._add_animal_risk(animal_risks, animal, 0.38 + severity * 0.35, severity * 0.007, "same-species territorial conflict")

        for animal in living:
            spec = self.species[animal["species_id"]]
            social = str(spec.get("social", ""))
            if ("cave" in social or "shy" in social or spec.get("swim_zone") == "bottom") and hiding < 0.28:
                self._add_animal_risk(animal_risks, animal, 0.28, 0.0015, "not enough hiding cover")
            if spec.get("activity", 0.0) > 0.75 and open_swimming < 0.45:
                self._add_animal_risk(animal_risks, animal, 0.24, 0.001, "not enough open swimming room")
            if spec.get("oxygen_min_mg_l", 5.0) >= 5.5 and current_strength < 0.32:
                self._add_animal_risk(animal_risks, animal, 0.22, 0.001, "too little flow for oxygen-loving fish")
            if animal["species_id"] in {"betta_splendens", "fancy_guppy"} and current_strength > 0.82:
                self._add_animal_risk(animal_risks, animal, 0.24, 0.001, "current is tiring long-finned fish")

        for attacker in living:
            attacker_spec = self.species[attacker["species_id"]]
            for target in living:
                if attacker["id"] == target["id"]:
                    continue
                target_spec = self.species[target["species_id"]]
                size_ratio = attacker_spec.get("adult_cm", 0.0) / max(0.5, target_spec.get("adult_cm", 0.0))
                attacker_territory = float(attacker_spec.get("territoriality", 0.0)) * (0.65 + float(attacker.get("territory_claim", 0.2)))
                target_long_finned = target["species_id"] in {"betta_splendens", "fancy_guppy"} or float(target_spec.get("fin_nipping", 0.0)) < 0.03 and target_spec.get("activity", 0.5) < 0.5
                if attacker_spec.get("fin_nipping", 0.0) > 0.16 and target_long_finned:
                    nip = float(attacker_spec.get("fin_nipping", 0.0))
                    self._add_animal_risk(animal_risks, target, 0.22 + nip * 0.25, 0.0015 + nip * 0.002, "fin nipping risk")
                    self._add_injury_risk(animal_risks, target, 0.001 + nip * 0.002, "minor fin damage")
                if size_ratio > 2.15 and attacker_spec.get("predator_mouth_cm", 0.0) > target_spec.get("adult_cm", 0.0) * 0.14:
                    pressure = clamp((size_ratio - 2.0) / 2.2, 0.0, 1.0)
                    self._add_animal_risk(animal_risks, target, 0.34 + pressure * 0.28, 0.002 + pressure * 0.004, "predation intimidation")
                if attacker_territory > 0.38 and target_spec.get("swim_zone") == attacker_spec.get("swim_zone") and hiding < 0.45:
                    pressure = clamp(attacker_territory + (0.45 - hiding), 0.0, 1.0)
                    self._add_animal_risk(animal_risks, target, 0.18 + pressure * 0.26, pressure * 0.002, "territory overlap")
                    if pressure > 0.55:
                        self._add_injury_risk(animal_risks, target, pressure * 0.0015, "territorial chasing")
                rank_gap = float(attacker.get("feeding_rank", 0.5)) - float(target.get("feeding_rank", 0.5))
                if rank_gap > 0.45 and target.get("hunger", 0.0) > 0.65:
                    self._add_animal_risk(animal_risks, target, 0.16 + rank_gap * 0.22, 0.0008, "outcompeted at feeding")

        worst_stress = max((float(risk["stress"]) for risk in animal_risks.values()), default=0.0)
        total_damage = sum(float(risk["damage_per_hour"]) + float(risk.get("injury_per_hour", 0.0)) * 1.8 for risk in animal_risks.values())
        score = int(clamp(100 - worst_stress * 55 - total_damage * 260, 0, 100))
        status = "critical" if score < 45 or any(i["severity"] == "critical" for i in issues) else "watch" if issues or score < 75 else "stable"
        return {"score": score, "status": status, "issues": issues[:10], "animal_risks": animal_risks}

    def _tick(self, seconds: float) -> None:
        hours = seconds / 3600.0
        variability = float(self._randomness().get("noise", 0.12))
        water = self.state["water"]
        bio = self.state["biology"]
        equipment = self.state["equipment"]
        food = self.state["food"]
        planning = self._evaluate_planning()
        self._maintenance_status()
        self.state["aquarium"].update(self._scape_metrics())
        scape_metrics = self.state["aquarium"]
        self._decompose_dead_animals(hours)
        living = [a for a in self.state["animals"] if a["alive"]]
        total_bioload = sum(self.species[a["species_id"]]["bioload"] for a in living)

        appetite_demand = sum(max(0.0, a["hunger"] - 0.2) * float(a.get("appetite_bias", 1.0)) for a in living)
        consumed = min(food["available"], appetite_demand * hours * 0.32 * self._noise_multiplier(variability * 0.65, "feeding"))
        feeding_shares = self._feeding_distribution(living, consumed)
        food["available"] -= consumed
        leftover_decay = min(
            food["available"],
            max(0.0, food["available"] - 0.08) * hours * 0.018 * self._noise_multiplier(variability * 0.45, "food_decay"),
        )
        food["available"] = max(0.0, food["available"] - leftover_decay)
        food["decaying"] += leftover_decay
        mineralized_food = min(food["decaying"], food["decaying"] * hours * 0.010 * self._noise_multiplier(variability * 0.35, "food_mineralization"))
        food["decaying"] = max(0.0, food["decaying"] - mineralized_food * 0.72)
        if food["available"] > 0.9 or food["decaying"] > 0.55:
            self._record_once("overfeeding", "warning", "Uneaten food is decaying", "Overfeeding is producing extra ammonia risk. Feed less and remove leftovers.")
        substrate_depth = float(self.state["aquarium"].get("substrate_depth_cm", 5.0))
        substrate_trap = clamp((substrate_depth - 3.0) / 5.0, 0.0, 0.55)
        waste_input = (
            total_bioload * 0.00055 * hours
            + mineralized_food * 0.06
            + water["organic_waste"] * hours * 0.00035
        ) * self._noise_multiplier(variability * 0.5, "waste_input")
        water["organic_waste"] = clamp(water["organic_waste"] + waste_input * 0.45 + leftover_decay * 0.35 + mineralized_food * 0.32 + scape_metrics["maintenance_load"] * hours * 0.0012, 0, 5)
        water["organic_waste"] = clamp(water["organic_waste"] + substrate_trap * water["organic_waste"] * hours * 0.001, 0, 5)
        water["detritus"] = clamp(water.get("detritus", 0.0) + (leftover_decay + waste_input) * hours * 0.018 + substrate_trap * hours * 0.00035, 0, 1)
        water["surface_film"] = clamp(water.get("surface_film", 0.0) + (food["available"] + food["decaying"] + water["organic_waste"]) * hours * 0.00075 - scape_metrics["surface_agitation"] * hours * 0.0022, 0, 1)
        water["ammonia_mg_l"] += waste_input
        maturity = self.state.get("maturity", {})
        water["phosphate_mg_l"] = clamp(
            water.get("phosphate_mg_l", 0.0)
            + mineralized_food * 0.010
            + water["organic_waste"] * hours * 0.00012
            + float(maturity.get("mulm", 0.0)) * hours * 0.00016,
            0,
            10,
        )
        self._update_equipment(hours)

        filter_state = equipment["filter"]
        media = filter_state.setdefault("media", default_filter()["media"])
        mechanical = media.setdefault("mechanical", default_filter()["media"]["mechanical"].copy())
        biological = media.setdefault("biological", default_filter()["media"]["biological"].copy())
        chemical = media.setdefault("chemical", default_filter()["media"]["chemical"].copy())
        clog = clamp(float(mechanical.get("clog", 0.0)), 0, 1)
        mechanical_condition = clamp(float(mechanical.get("condition", 0.8)), 0, 1)
        flow_jitter = self._noise_multiplier(variability * 0.15, "filter_flow_jitter")
        effective_flow = clamp(float(filter_state["flow"]) * flow_jitter * (1.0 - clog * 0.58) * float(filter_state["health"]), 0.04, 1.0)
        filter_state["effective_flow"] = effective_flow
        biological["oxygen_access"] = clamp(effective_flow * water["oxygen_mg_l"] / 7.0, 0.05, 1.2)
        biological_maturity = clamp(float(biological.get("maturity", filter_state.get("maturity", 0.8))), 0.05, 1.0)
        alkalinity = float(water.get("alkalinity_dkh", water.get("kh_dkh", 4.0)))
        alkalinity_factor = clamp(alkalinity / 4.0, 0.18, 1.18)
        ph_factor = clamp((water["ph"] - 5.8) / 2.2, 0.08, 1.08)
        filter_factor = (
            float(filter_state["enabled"])
            * filter_state["health"]
            * effective_flow
            * filter_state["maturity"]
            * biological_maturity
            * biological.get("surface_area", 1.0)
            * biological["oxygen_access"]
            * alkalinity_factor
            * ph_factor
        )
        disinfectant = clamp(float(water.get("chlorine_mg_l", 0.0)) + float(water.get("chloramine_mg_l", 0.0)) * 1.25, 0.0, 2.0)
        if disinfectant > 0.0:
            damage = min(0.18, disinfectant * hours * 0.025)
            bio["ammonia_bacteria"] = clamp(bio["ammonia_bacteria"] - damage, 0.01, 1.0)
            bio["nitrite_bacteria"] = clamp(bio["nitrite_bacteria"] - damage * 0.9, 0.01, 1.0)
            biological["maturity"] = clamp(float(biological.get("maturity", 0.8)) - damage * 0.55, 0.02, 1.0)
        oxygen_factor = clamp(water["oxygen_mg_l"] / 7.0, 0.1, 1.2)
        ammonia_conversion = min(
            water["ammonia_mg_l"],
            bio["ammonia_bacteria"] * filter_factor * oxygen_factor * hours * 0.045 * self._noise_multiplier(variability * 0.55, "ammonia_bacteria_conversion"),
        )
        water["ammonia_mg_l"] -= ammonia_conversion
        water["nitrite_mg_l"] += ammonia_conversion
        nitrite_conversion = min(
            water["nitrite_mg_l"],
            bio["nitrite_bacteria"] * filter_factor * oxygen_factor * hours * 0.04 * self._noise_multiplier(variability * 0.55, "nitrite_bacteria_conversion"),
        )
        water["nitrite_mg_l"] -= nitrite_conversion
        water["nitrate_mg_l"] += nitrite_conversion
        nitrified = ammonia_conversion + nitrite_conversion
        water["oxygen_mg_l"] = clamp(water["oxygen_mg_l"] - nitrified * 0.05, 0, 10)
        water["kh_dkh"] = clamp(water["kh_dkh"] - nitrified * 0.018, 0, 20)
        water["alkalinity_dkh"] = clamp(float(water.get("alkalinity_dkh", water["kh_dkh"])) - nitrified * 0.018, 0, 20)

        trapped = min(water["organic_waste"], effective_flow * mechanical_condition * hours * 0.009)
        water["organic_waste"] -= trapped
        water["turbidity"] = clamp(water["turbidity"] - effective_flow * mechanical_condition * hours * 0.012, 0, 1)
        mechanical["clog"] = clamp(clog + (trapped * 0.18 + water["turbidity"] * 0.006 + food["decaying"] * 0.01) * hours, 0, 1)
        mechanical["condition"] = clamp(mechanical_condition - mechanical["clog"] * hours * 0.0008, 0.15, 1)
        carbon = clamp(float(chemical.get("carbon_remaining", 0.0)), 0, 1)
        if carbon > 0:
            polish = min(water["organic_waste"], carbon * effective_flow * hours * 0.0025)
            water["organic_waste"] -= polish
            water["turbidity"] = clamp(water["turbidity"] - carbon * effective_flow * hours * 0.002, 0, 1)
            chemical["carbon_remaining"] = clamp(carbon - (polish * 0.04 + hours * 0.00025), 0, 1)
        phosphate_media = clamp(float(chemical.get("phosphate_remover_remaining", 0.0)), 0, 1)
        if phosphate_media > 0 and filter_state.get("enabled", True):
            phosphate_removed = min(water.get("phosphate_mg_l", 0.0), phosphate_media * effective_flow * hours * 0.0022)
            water["phosphate_mg_l"] = clamp(water.get("phosphate_mg_l", 0.0) - phosphate_removed, 0, 10)
            chemical["phosphate_remover_remaining"] = clamp(phosphate_media - (phosphate_removed * 0.18 + hours * 0.00015), 0, 1)

        bacterial_food = clamp((water["ammonia_mg_l"] + water["nitrite_mg_l"]) * 2.0, 0, 1)
        bio["ammonia_bacteria"] = clamp(bio["ammonia_bacteria"] + (bacterial_food - 0.2) * hours * 0.002, 0.05, 1)
        bio["nitrite_bacteria"] = clamp(bio["nitrite_bacteria"] + (bacterial_food - 0.2) * hours * 0.0018, 0.05, 1)
        plant_uptake = bio["plant_health"] * scape_metrics["nitrate_uptake"] * hours * 0.015 * self._noise_multiplier(variability * 0.7, "plant_nitrate_uptake")
        water["nitrate_mg_l"] = max(0.0, water["nitrate_mg_l"] - plant_uptake)
        phosphate_uptake = bio["plant_health"] * scape_metrics["nitrate_uptake"] * hours * 0.00055 * self._noise_multiplier(variability * 0.7, "plant_phosphate_uptake")
        water["phosphate_mg_l"] = clamp(water.get("phosphate_mg_l", 0.0) - phosphate_uptake, 0, 10)

        lights_on, light_hours = self._lighting_window()
        self._update_evaporation_and_skimmer(hours, lights_on)
        sunlight_hours = float(planning.get("direct_sunlight_hours", 0.0))
        if sunlight_hours > 0:
            water["temperature_c"] += sunlight_hours * hours * 0.004
        surface_film_penalty = clamp(1.0 - water.get("surface_film", 0.0) * 0.55, 0.35, 1.0)
        co2_target = 3.0 + water["organic_waste"] * 0.75 + total_bioload * 0.08
        if lights_on:
            co2_target -= bio["plant_health"] * scape_metrics["nitrate_uptake"] * 1.6
        else:
            co2_target += bio["plant_health"] * max(0.0, scape_metrics["plant_cover"]) * 1.15
        co2_outgassing = (scape_metrics["surface_agitation"] * 0.11 + float(equipment["air_pump"].get("enabled", True)) * equipment["air_pump"].get("output", 0.5) * 0.12) * surface_film_penalty
        water["co2_mg_l"] = clamp(float(water.get("co2_mg_l", 4.0)) + (co2_target - float(water.get("co2_mg_l", 4.0))) * hours * 0.045 - co2_outgassing * hours, 0.3, 45.0)
        oxygen_gain = (
            self.state["aquarium"]["surface_agitation"] * 0.18 * surface_film_penalty
            + float(equipment["air_pump"].get("enabled", True)) * equipment["air_pump"].get("output", 0.5) * equipment["air_pump"].get("health", 1.0) * 0.17
            + bio["plant_health"] * (scape_metrics["oxygen_day"] if lights_on else scape_metrics["oxygen_night"])
        )
        oxygen_use = total_bioload * 0.008 + water["organic_waste"] * 0.018 + water.get("surface_film", 0.0) * 0.008 + water.get("co2_mg_l", 4.0) * 0.0008
        water["oxygen_mg_l"] = clamp(water["oxygen_mg_l"] + (oxygen_gain - oxygen_use) * hours * self._noise_multiplier(variability * 0.25, "gas_exchange"), 0, 10)

        heater = equipment["heater"]
        ambient = 21.0
        target = heater["target_c"] if heater["enabled"] and heater["health"] > 0.15 else ambient
        heater_efficiency = 1.0 if heater.get("placement_near_flow", True) else 0.55
        room_swing = float(planning.get("room_temp_swing_c", 0.0))
        water["temperature_c"] += (target - water["temperature_c"]) * min(1.0, hours * 0.12 * heater_efficiency)
        water["temperature_c"] += math.sin(time.time() / 3600.0) * room_swing * hours * 0.003
        water["turbidity"] = clamp(water["turbidity"] + water["organic_waste"] * hours * 0.002 - filter_factor * hours * 0.01, 0, 1)
        water["tannins"] = clamp(water.get("tannins", 0.0) + scape_metrics.get("soft_water", 0.0) * hours * 0.002 - hours * 0.0007, 0, 1)
        kh = float(water.get("kh_dkh", water.get("alkalinity_dkh", 4.0)))
        co2_pressure = max(0.0, water.get("co2_mg_l", 4.0) - 5.0) / max(2.0, kh + 1.0)
        water["ph"] = clamp(water["ph"] - water["organic_waste"] * hours * 0.00025 - scape_metrics.get("soft_water", 0.0) * hours * 0.0009 - co2_pressure * hours * 0.00055 + (kh - 4) * hours * 0.0001, 4.5, 9)
        light_excess = max(0.0, light_hours + sunlight_hours - 8.0)
        light_shortage = max(0.0, 5.0 - light_hours)
        bio["algae"] = clamp(
            bio["algae"]
            + (0.005 if lights_on else -0.001) * hours
            + light_excess * hours * 0.0015
            + water.get("phosphate_mg_l", 0.0) * hours * 0.00035
            + water["nitrate_mg_l"] * hours * 0.00005
            - scape_metrics["algae_control"] * hours * 0.002,
            0,
            1,
        )
        bio["plant_health"] = clamp(bio["plant_health"] - light_shortage * hours * 0.0008 + (0.0003 if 6.0 <= light_hours <= 8.5 else 0.0) * hours, 0.1, 1.0)
        self._update_plants_and_corals(hours, lights_on, light_hours)

        groups = self._groups(living)
        welfare = self._community_welfare(living, groups)
        self.state["welfare"] = welfare
        for animal in living:
            self._update_animal(animal, groups, welfare, float(feeding_shares.get(animal["id"], 0.0)), hours)
        self._maybe_breeding_events(living, groups, hours)
        self._update_nursery(hours)
        self._update_cycle(hours)
        self._update_tank_maturity(hours)
        self._apply_random_ecosystem_events(hours, living, filter_state, mechanical)

        for item in equipment.values():
            if isinstance(item, dict) and "health" in item:
                item["health"] = clamp(item["health"] - hours * 0.00002, 0, 1)
        filter_state["flow"] = clamp(filter_state["flow"] - water["organic_waste"] * hours * 0.00008 - mechanical["clog"] * hours * 0.00005, 0.08, 1)
        self._update_symptoms()
        self._check_emergencies()

    def _apply_random_ecosystem_events(self, hours: float, living: list[dict[str, Any]], filter_state: dict[str, Any], mechanical: dict[str, Any]) -> None:
        water = self.state["water"]
        bio = self.state["biology"]
        equipment = self.state["equipment"]
        clog = clamp(float(mechanical.get("clog", 0.0)), 0.0, 1.0)
        organic = float(water.get("organic_waste", 0.0))
        turbidity_rate = 0.001 + clog * 0.01 + max(0.0, organic - 0.8) * 0.006 + max(0.0, 0.7 - float(filter_state.get("health", 1.0))) * 0.006
        if self._chance(turbidity_rate, hours, "filter_burp"):
            water["turbidity"] = clamp(water["turbidity"] + 0.04 + clog * 0.08, 0, 1)
            mechanical["clog"] = clamp(clog + 0.025, 0, 1)
            self._random_note("Filter released trapped debris")
            self._record_once("random_filter_burp", "warning", "Filter released trapped debris", "A pocket of trapped waste clouded the water. Service the mechanical media if clogging keeps rising.")

        heater = equipment.get("heater", {})
        heater_rate = max(0.0, 1.0 - float(heater.get("health", 1.0))) * 0.012
        if self._chance(heater_rate, hours, "heater_drift"):
            direction = -1.0 if self._rng("heater_direction").random() < 0.5 else 1.0
            water["temperature_c"] = clamp(water["temperature_c"] + direction * self._rng("heater_amount").uniform(0.08, 0.28), 8, 36)
            self._random_note("Heater drifted slightly")

        light = equipment.get("light", {})
        timer_rate = 0.0006 if light.get("timer_enabled", True) else 0.004
        if self._chance(timer_rate, hours, "lighting_timer_miss"):
            bio["algae"] = clamp(bio.get("algae", 0.0) + 0.015, 0, 1)
            self._random_note("Lighting ran a little long")
            self._record_once("random_light_timer", "warning", "Lighting ran long", "A timer or schedule wobble slightly increased algae pressure.")

        microbial_rate = max(0.0, organic - 1.2) * 0.01 + max(0.0, water.get("phosphate_mg_l", 0.0) - 1.0) * 0.003
        if self._chance(microbial_rate, hours, "microbial_bloom"):
            water["oxygen_mg_l"] = clamp(water["oxygen_mg_l"] - 0.12, 0, 10)
            water["turbidity"] = clamp(water["turbidity"] + 0.05, 0, 1)
            self._random_note("Bacterial bloom pressure rose")
            self._record_once("random_microbe_bloom", "warning", "Bacterial bloom pressure rose", "High organics allowed a small microbial bloom, reducing clarity and oxygen.")

        for animal in living:
            self._maybe_update_disease(animal, hours)

    def _update_tank_maturity(self, hours: float) -> None:
        maturity = self.state.setdefault("maturity", default_maturity(float(self.state.get("cycle", {}).get("days_running", 0.0))))
        water = self.state["water"]
        bio = self.state["biology"]
        cycle_days = float(self.state.get("cycle", {}).get("days_running", 0.0))
        stability = 1.0 - clamp(
            water.get("ammonia_mg_l", 0.0) * 2.5
            + water.get("nitrite_mg_l", 0.0) * 2.0
            + water.get("chlorine_mg_l", 0.0) * 1.8
            + float(maturity.get("last_water_change_shock", 0.0)) * 0.55,
            0.0,
            1.0,
        )
        maturity["seasoning"] = clamp(cycle_days / 180.0, 0.0, 1.0)
        maturity["biofilm"] = clamp(float(maturity.get("biofilm", 0.0)) + hours * 0.0013 * stability - water.get("chlorine_mg_l", 0.0) * hours * 0.01, 0.0, 1.0)
        maturity["microfauna"] = clamp(float(maturity.get("microfauna", 0.0)) + hours * 0.0009 * stability * float(maturity.get("biofilm", 0.0)) - float(maturity.get("last_water_change_shock", 0.0)) * hours * 0.002, 0.0, 1.0)
        maturity["mulm"] = clamp(float(maturity.get("mulm", 0.0)) + water.get("organic_waste", 0.0) * hours * 0.0007 + len([a for a in self.state.get("animals", []) if a.get("alive", True)]) * hours * 0.000015, 0.0, 1.0)
        maturity["plant_rooting"] = clamp(float(maturity.get("plant_rooting", 0.0)) + hours * 0.0008 * bio.get("plant_health", 0.8) - float(maturity.get("last_water_change_shock", 0.0)) * hours * 0.0008, 0.0, 1.0)
        algae_pressure = bio.get("algae", 0.0) + water.get("phosphate_mg_l", 0.0) * 0.08 + max(0.0, water.get("nitrate_mg_l", 0.0) - 20.0) * 0.003
        maturity["glass_algae"] = clamp(float(maturity.get("glass_algae", 0.0)) + algae_pressure * hours * 0.0009 - float(self.state["aquarium"].get("algae_control", 0.0)) * hours * 0.0005, 0.0, 1.0)
        maintenance_days = days_since(self.state.get("maintenance", {}).get("last_water_change", now_iso()), 0.0)
        old_pressure = max(0.0, cycle_days - 180.0) / 240.0 + max(0.0, maintenance_days - 21.0) / 30.0 + max(0.0, water.get("nitrate_mg_l", 0.0) - 35.0) / 55.0 + max(0.0, 2.0 - water.get("kh_dkh", 4.0)) / 4.0
        maturity["old_tank_risk"] = clamp(old_pressure, 0.0, 1.0)
        if float(maturity.get("biofilm", 0.0)) > 0.35:
            water["turbidity"] = clamp(water["turbidity"] - float(maturity["biofilm"]) * hours * 0.0009, 0.0, 1.0)
        if float(maturity.get("microfauna", 0.0)) > 0.25:
            water["organic_waste"] = clamp(water["organic_waste"] - float(maturity["microfauna"]) * hours * 0.00045, 0.0, 5.0)
        if float(maturity.get("mulm", 0.0)) > 0.65:
            water["nitrate_mg_l"] = clamp(water["nitrate_mg_l"] + float(maturity["mulm"]) * hours * 0.0014, 0.0, 200.0)
        maturity["last_water_change_shock"] = max(0.0, float(maturity.get("last_water_change_shock", 0.0)) - hours * 0.012)
        if float(maturity.get("old_tank_risk", 0.0)) > 0.55:
            self._record_once("old_tank_risk", "warning", "Old-tank pressure is building", "Long-term nitrate, mulm, low alkalinity, or delayed maintenance is making the mature aquarium less stable.")

    def _update_equipment(self, hours: float) -> None:
        equipment = self.state["equipment"]
        water = self.state["water"]
        filter_state = equipment.setdefault("filter", default_filter())
        media = filter_state.setdefault("media", default_filter()["media"])
        mechanical = media.setdefault("mechanical", default_filter()["media"]["mechanical"].copy())
        clog = float(mechanical.get("clog", 0.0))
        if clog > 0.78 and filter_state.get("failure_mode", "") == "":
            filter_state["failure_mode"] = "impeller strain"
            filter_state["noise"] = clamp(float(filter_state.get("noise", 0.12)) + 0.34, 0, 1)
            self._record_once("filter_impeller_strain", "warning", "Filter is straining", "Mechanical media is heavily clogged; flow is uneven and the impeller is under load.")
        if filter_state.get("failure_mode") == "impeller strain":
            filter_state["health"] = clamp(float(filter_state.get("health", 1.0)) - hours * 0.0007, 0, 1)
            filter_state["flow"] = clamp(float(filter_state.get("flow", 0.7)) - hours * 0.00022, 0.04, 1)
            water["turbidity"] = clamp(water["turbidity"] + hours * 0.0012, 0, 1)
        heater = equipment.setdefault("heater", {"enabled": True, "health": 0.98, "target_c": 24.0, "placement_near_flow": True, "thermometer_present": True})
        if heater.get("enabled", True) and float(heater.get("health", 1.0)) < 0.42 and heater.get("failure_mode", "") == "":
            heater["failure_mode"] = "thermostat drift"
            self._record_once("heater_drift_failure", "warning", "Heater thermostat is drifting", "The heater is aging; temperature will become less stable until replaced or disabled.")
        if heater.get("failure_mode") == "thermostat drift":
            drift = math.sin(time.time() / 1800.0) * (0.35 + (0.42 - float(heater.get("health", 0.42))) * 1.2)
            heater["target_c"] = clamp(float(heater.get("target_c", 24.0)) + drift * hours * 0.004, 16, 32)
        light = equipment.setdefault("light", {"enabled": True, "health": 0.99, "hours_per_day": 8.0, "timer_enabled": True, "plant_spectrum": 0.82})
        if light.get("enabled", True) and float(light.get("health", 1.0)) < 0.38 and light.get("failure_mode", "") == "":
            light["failure_mode"] = "weak spectrum"
            light["plant_spectrum"] = clamp(float(light.get("plant_spectrum", 0.82)) - 0.22, 0, 1)
            self._record_once("light_spectrum_failure", "warning", "Lighting spectrum is weakening", "Plant/coral growth will slow because the lamp output is degrading.")
        pump = equipment.setdefault("air_pump", {"enabled": True, "health": 0.97, "output": 0.5})
        if pump.get("enabled", True) and float(pump.get("health", 1.0)) < 0.35 and pump.get("failure_mode", "") == "":
            pump["failure_mode"] = "diaphragm wear"
            pump["output"] = clamp(float(pump.get("output", 0.5)) * 0.65, 0, 1)
            self._record_once("air_pump_wear", "warning", "Air pump output is weak", "Aging air pump output reduced gas exchange.")

    def _update_evaporation_and_skimmer(self, hours: float, lights_on: bool) -> None:
        equipment = self.state["equipment"]
        water = self.state["water"]
        aquarium = self.state["aquarium"]
        surface_factor = clamp(float(aquarium.get("surface_agitation", 0.5)) + float(equipment.get("air_pump", {}).get("output", 0.0)) * 0.25, 0.25, 1.4)
        heat_factor = clamp((float(water.get("temperature_c", 24.0)) - 18.0) / 12.0, 0.2, 1.5)
        light_factor = 1.18 if lights_on else 0.86
        evaporation = hours * 0.00028 * surface_factor * heat_factor * light_factor
        old_level = max(0.55, float(water.get("water_level", 1.0)))
        new_level = clamp(old_level - evaporation, 0.55, 1.0)
        if new_level < old_level:
            concentration = old_level / max(new_level, 0.55)
            water["water_level"] = new_level
            water["tds_mg_l"] = clamp(float(water.get("tds_mg_l", 180.0)) * concentration, 0, 45000)
            if water.get("system") == "saltwater":
                water["salinity_ppt"] = clamp(float(water.get("salinity_ppt", 35.0)) * concentration, 0, 45)
        ato = equipment.setdefault("auto_top_off", {"enabled": False, "health": 0.96, "reservoir_litres": 5.0})
        if bool(ato.get("enabled", False)) and float(ato.get("health", 1.0)) > 0.2 and water.get("water_level", 1.0) < 0.985:
            needed = 1.0 - float(water.get("water_level", 1.0))
            litres_needed = needed * float(aquarium.get("gross_litres", 60.0))
            available = max(0.0, float(ato.get("reservoir_litres", 0.0)))
            refill_fraction = min(needed, available / max(1.0, float(aquarium.get("gross_litres", 60.0))))
            if refill_fraction > 0:
                self.top_off(refill_fraction, quiet=True)
                ato["reservoir_litres"] = max(0.0, available - min(available, litres_needed))
            else:
                self._record_once("ato_empty", "warning", "Top-off reservoir is empty", "Evaporation is concentrating minerals and salinity because the ATO reservoir ran dry.")
        skimmer = equipment.setdefault("protein_skimmer", {"enabled": water.get("system") == "saltwater", "health": 0.95, "output": 0.55, "cup_fullness": 0.0})
        if water.get("system") == "saltwater" and bool(skimmer.get("enabled", True)) and float(skimmer.get("health", 1.0)) > 0.1:
            output = clamp(float(skimmer.get("output", 0.55)) * float(skimmer.get("health", 1.0)) * (1.0 - float(skimmer.get("cup_fullness", 0.0)) * 0.55), 0, 1)
            export = min(float(water.get("organic_waste", 0.0)), output * hours * 0.006)
            water["organic_waste"] = clamp(float(water.get("organic_waste", 0.0)) - export, 0, 5)
            water["surface_film"] = clamp(float(water.get("surface_film", 0.0)) - output * hours * 0.004, 0, 1)
            water["turbidity"] = clamp(float(water.get("turbidity", 0.0)) - output * hours * 0.002, 0, 1)
            skimmer["cup_fullness"] = clamp(float(skimmer.get("cup_fullness", 0.0)) + export * 0.22 + hours * 0.00035, 0, 1)
            if float(skimmer.get("cup_fullness", 0.0)) > 0.88:
                self._record_once("skimmer_cup_full", "warning", "Skimmer cup is full", "Protein skimmer export is weakening because the collection cup needs emptying.")

    def _decompose_dead_animals(self, hours: float) -> None:
        water = self.state["water"]
        for animal in self.state.get("animals", []):
            if animal.get("alive", True):
                continue
            remaining = float(animal.get("death_load_remaining", 0.0))
            if remaining <= 0:
                continue
            release = min(remaining, hours * 0.022)
            animal["death_load_remaining"] = remaining - release
            animal["decomposition_hours"] = float(animal.get("decomposition_hours", 0.0)) + hours
            water["ammonia_mg_l"] += release * 0.45
            water["organic_waste"] = clamp(water["organic_waste"] + release * 0.8, 0, 5)
            water["phosphate_mg_l"] = clamp(water.get("phosphate_mg_l", 0.0) + release * 0.12, 0, 10)
            water["turbidity"] = clamp(water["turbidity"] + release * 0.08, 0, 1)

    def _feeding_distribution(self, living: list[dict[str, Any]], consumed: float) -> dict[str, float]:
        if consumed <= 0 or not living:
            return {}
        scores: dict[str, float] = {}
        total = 0.0
        for animal in living:
            spec = self.species.get(animal.get("species_id", ""), {})
            hunger = max(0.0, float(animal.get("hunger", 0.0)) - 0.12)
            rank = float(animal.get("feeding_rank", 0.55))
            boldness = float(animal.get("boldness", 0.5))
            stress_penalty = 1.0 - clamp(float(animal.get("acute_stress", 0.0)) * 0.55 + float(animal.get("injury", 0.0)) * 0.35, 0.0, 0.82)
            zone_bonus = 1.12 if spec.get("swim_zone") in {"upper", "middle"} else 0.86
            score = max(0.001, hunger * float(animal.get("appetite_bias", 1.0)) * (0.55 + rank * 0.55 + boldness * 0.35) * stress_penalty * zone_bonus)
            scores[animal["id"]] = score
            total += score
        shares: dict[str, float] = {}
        for animal_id, score in scores.items():
            shares[animal_id] = consumed * score / max(total, 0.001)
        return shares

    def _maybe_breeding_events(self, living: list[dict[str, Any]], groups: dict[str, int], hours: float) -> None:
        if not living:
            return
        water = self.state["water"]
        aquarium = self.state["aquarium"]
        if water.get("ammonia_mg_l", 0.0) > 0.02 or water.get("nitrite_mg_l", 0.0) > 0.02 or water.get("nitrate_mg_l", 0.0) > 28:
            return
        cover = float(aquarium.get("hiding_cover", 0.0)) + float(aquarium.get("plant_cover", 0.0)) * 0.5
        if cover < 0.28:
            return
        for species_id, count in groups.items():
            if count < 2:
                continue
            members = [a for a in living if a.get("species_id") == species_id and float(a.get("breeding_condition", 0.0)) > 0.74 and float(a.get("spawn_cooldown_days", 30.0)) <= 0.0]
            sexes = {str(a.get("sex", "")) for a in members}
            if len(members) < 2 or not {"male", "female"}.issubset(sexes):
                continue
            spec = self.species.get(species_id, {})
            social_ok = count >= max(1, int(spec.get("minimum_group", 1)))
            if not social_ok:
                continue
            survival = clamp(cover * 0.55 + (1.0 - float(self.state["biology"].get("algae", 0.0))) * 0.2 - water.get("organic_waste", 0.0) * 0.06, 0.02, 0.65)
            rate = 0.0012 * survival
            if species_id in {"fancy_guppy", "platy"}:
                rate *= 2.4
            if self._chance(rate, hours, f"spawn_{species_id}"):
                parent = members[0]
                parent["spawn_cooldown_days"] = 21.0 if species_id in {"fancy_guppy", "platy"} else 38.0
                parent["breeding_condition"] = 0.25
                self.state.setdefault("nursery", []).append({
                    "species_id": species_id,
                    "count": max(1, int(2 + survival * 8)),
                    "age_days": 0.0,
                    "survival_chance": survival,
                    "created_at": now_iso(),
                })
                self._record("info", f"{spec.get('common_name', species_id)} spawned", "Stable water, cover, good food, and compatible adults produced eggs or fry. Survival will depend on cover and water quality.")

    def _update_nursery(self, hours: float) -> None:
        nursery = self.state.setdefault("nursery", [])
        if not nursery:
            return
        water = self.state["water"]
        survivors: list[dict[str, Any]] = []
        for brood in nursery:
            species_id = str(brood.get("species_id", ""))
            spec = self.species.get(species_id, {})
            brood["age_days"] = float(brood.get("age_days", 0.0)) + hours / 24.0
            stress = clamp(water.get("ammonia_mg_l", 0.0) * 2.5 + water.get("nitrite_mg_l", 0.0) * 2.0 + max(0.0, water.get("nitrate_mg_l", 0.0) - 20.0) / 35.0 + water.get("organic_waste", 0.0) * 0.08, 0.0, 1.0)
            survival = clamp(float(brood.get("survival_chance", 0.2)) - stress * hours * 0.002, 0.0, 1.0)
            brood["survival_chance"] = survival
            count = int(brood.get("count", 0))
            water["organic_waste"] = clamp(water["organic_waste"] + count * hours * 0.00002, 0, 5)
            if survival <= 0.04 or count <= 0:
                self._record_once(f"nursery_loss_{species_id}", "warning", f"{spec.get('common_name', species_id)} brood failed", "Eggs or fry were lost because cover, stability, or water quality was not good enough.")
                continue
            if float(brood["age_days"]) >= 45.0:
                recruits = max(1, min(count, int(round(count * survival))))
                for i in range(recruits):
                    baby = make_animal(spec, f"Young {spec.get('common_name', species_id)} {i + 1}", int(time.time() * 1000) % 100000 + i)
                    baby["age_days"] = 45
                    baby["size_cm"] = float(spec.get("adult_cm", 3.0)) * 0.36
                    baby["health"] = clamp(0.62 + survival * 0.32, 0, 1)
                    baby["behavior"] = "juvenile exploring cover"
                    self.state["animals"].append(baby)
                self._record("info", f"{spec.get('common_name', species_id)} fry survived", f"{recruits} juveniles are now large enough to appear in the aquarium.")
            else:
                survivors.append(brood)
        self.state["nursery"] = survivors

    def _apply_death_load(self, animal: dict[str, Any], immediate: bool = False) -> None:
        spec = self.species.get(animal.get("species_id", ""), {})
        load = spec.get("bioload", 0.6) * (0.28 if immediate else 0.18)
        animal["death_load_remaining"] = float(animal.get("death_load_remaining", 0.0)) + load
        animal["decomposition_hours"] = 0.0
        if immediate:
            water = self.state["water"]
            water["ammonia_mg_l"] += load * 0.25
            water["organic_waste"] = clamp(water["organic_waste"] + load * 0.35, 0, 5)
            water["phosphate_mg_l"] = clamp(water.get("phosphate_mg_l", 0.0) + load * 0.05, 0, 10)
            water["turbidity"] = clamp(water["turbidity"] + load * 0.04, 0, 1)

    def _update_plants_and_corals(self, hours: float, lights_on: bool, light_hours: float) -> None:
        water = self.state["water"]
        aquarium = self.state["aquarium"]
        bio = self.state["biology"]
        light = self.state.get("equipment", {}).get("light", {})
        spectrum = clamp(float(light.get("plant_spectrum", 0.82)) if light.get("enabled", True) else 0.0, 0.0, 1.0)
        substrate = str(aquarium.get("substrate", "fine_sand"))
        depth = float(aquarium.get("substrate_depth_cm", 5.0))
        nutrient = clamp((water.get("nitrate_mg_l", 0.0) / 18.0 + water.get("phosphate_mg_l", 0.0) / 0.7) * 0.5, 0.0, 1.4)
        light_balance = (1.0 - clamp(abs(light_hours - 7.0) / 7.0, 0.0, 1.0)) * spectrum
        algae = float(bio.get("algae", 0.0))
        for group_name in ("plants",):
            for plant in aquarium["scape"].get(group_name, []):
                plant_type = str(plant.get("type", ""))
                info = PLANT_TYPES.get(plant_type, {})
                health = float(plant.get("health", 0.82))
                quantity = max(1.0, float(plant.get("quantity", 1)))
                root_penalty = 0.0
                if info.get("root_feeder") and (substrate in {"bare_bottom", "rounded_gravel"} or depth < 3.5):
                    root_penalty = 0.32
                shade_penalty = clamp(float(aquarium.get("surface_shade", 0.0)) * 0.45, 0.0, 0.45)
                melt_pressure = root_penalty + max(0.0, algae - 0.45) * 0.35 + max(0.0, 0.25 - nutrient) * 0.25 + max(0.0, 0.42 - light_balance) * 0.35
                growth_pressure = max(0.0, nutrient - 0.2) * light_balance * (1.0 - algae * 0.45)
                health = clamp(health + (growth_pressure * 0.006 - melt_pressure * 0.012) * hours, 0.0, 1.0)
                if health > 0.7 and growth_pressure > 0.25:
                    plant["quantity"] = int(clamp(quantity + hours * 0.008 * growth_pressure, 1, 120))
                if health < 0.28:
                    water["organic_waste"] = clamp(water["organic_waste"] + quantity * hours * 0.00025, 0, 5)
                    water["ammonia_mg_l"] = clamp(water["ammonia_mg_l"] + quantity * hours * 0.000035, 0, 5)
                    water["phosphate_mg_l"] = clamp(water.get("phosphate_mg_l", 0.0) + quantity * hours * 0.00002, 0, 10)
                    self._record_once(f"plant_melt_{plant_type}", "warning", f"{info.get('name', plant_type)} is melting", "Plant health is falling because light, nutrients, algae, or substrate conditions are wrong.")
                plant["health"] = health
        if water.get("system") == "saltwater":
            temp_stress = range_stress(water["temperature_c"], [24.0, 26.5], [22.5, 29.0])
            salinity_stress = range_stress(water.get("salinity_ppt", 35.0), [34.0, 36.0], [31.0, 38.0])
            nitrate_stress = clamp((water["nitrate_mg_l"] - 15.0) / 35.0, 0, 1)
            phosphate_stress = clamp((water.get("phosphate_mg_l", 0.0) - 0.18) / 0.5, 0, 1)
            for coral in aquarium["scape"].get("corals", []):
                self._update_coral_piece(coral, hours, light_hours, max(temp_stress, salinity_stress, nitrate_stress, phosphate_stress))
            for obj in aquarium["scape"].get("objects", []):
                if obj.get("category") == "corals":
                    self._update_coral_piece(obj, hours, light_hours, max(temp_stress, salinity_stress, nitrate_stress, phosphate_stress))

    def _update_coral_piece(self, coral: dict[str, Any], hours: float, light_hours: float, water_stress: float) -> None:
        water = self.state["water"]
        info = CORAL_TYPES.get(str(coral.get("type", "")), {})
        light_need = float(info.get("light_need", 0.55))
        light_match = 1.0 - clamp(abs((light_hours / 10.0) - light_need), 0.0, 1.0)
        flow = float(self.state.get("equipment", {}).get("filter", {}).get("effective_flow", 0.6))
        flow_stress = max(0.0, 0.26 - flow) + max(0.0, flow - 0.94) * 0.8
        stress = clamp(max(water_stress, flow_stress, max(0.0, 0.42 - light_match)), 0.0, 1.0)
        health = float(coral.get("health", 0.8))
        if stress <= 0.08:
            health = clamp(health + hours * 0.0015 * light_match, 0, 1)
            coral["quantity"] = int(clamp(float(coral.get("quantity", 1)) + hours * 0.002, 1, 80))
        else:
            health = clamp(health - stress * hours * 0.012, 0, 1)
        if health < 0.35:
            coral["bleached"] = True
            water["organic_waste"] = clamp(water["organic_waste"] + hours * 0.0008 * float(coral.get("quantity", 1)), 0, 5)
            self._record_once(f"coral_stress_{coral.get('type', '')}", "warning", f"{info.get('name', 'Coral')} is stressed", "Coral health is falling from light, flow, salinity, nutrient, or temperature pressure.")
        elif health > 0.62:
            coral["bleached"] = False
        coral["health"] = health

    def _maybe_update_disease(self, animal: dict[str, Any], hours: float) -> None:
        if not animal.get("alive", True):
            return
        water = self.state["water"]
        immune_gap = max(0.0, 0.78 - float(animal.get("immune_condition", 1.0)))
        chronic = float(animal.get("chronic_stress", 0.0))
        pathogen = float(animal.get("latent_pathogen_load", 0.02))
        nitrogen_pressure = clamp(water.get("ammonia_mg_l", 0.0) * 1.6 + water.get("nitrite_mg_l", 0.0) * 1.2, 0, 1.0)
        dirty_pressure = max(0.0, water.get("organic_waste", 0.0) - 0.8) * 0.18 + max(0.0, water.get("turbidity", 0.0) - 0.35) * 0.25
        salinity_pressure = 0.0
        spec = self.species.get(animal.get("species_id", ""), {})
        if water.get("system") == "saltwater":
            ideal = spec.get("salinity_ppt", {"ideal": [34.0, 36.0]}).get("ideal", [34.0, 36.0])
            salinity_pressure = range_stress(water.get("salinity_ppt", 35.0), ideal, [30.0, 39.0])
        injury_pressure = float(animal.get("injury", 0.0))
        acclimation_pressure = 0.35 if not animal.get("acclimated", True) else 0.0
        water_pressure = (
            nitrogen_pressure
            + dirty_pressure
            + salinity_pressure * 0.35
            + acclimation_pressure
            + max(0.0, injury_pressure - 0.15) * 0.25
        )
        disease_resistance = max(0.2, float(animal.get("disease_resistance", 1.0)))
        if animal.get("disease"):
            recovery_rate = max(0.0, 0.012 * disease_resistance - chronic * 0.01 - water_pressure * 0.008)
            if self._chance(recovery_rate, hours, f"disease_recovery_{animal['id']}"):
                animal["disease"] = ""
                animal["last_random_event"] = "recovered from opportunistic infection"
                self._random_note(f"{animal['name']} recovered")
                self._record("info", f"{animal['name']} recovered", "Stable water and reduced stress allowed the immune system to recover.", animal["id"])
            return

        disease_rate = (immune_gap * 0.04 + max(0.0, chronic - 0.25) * 0.035 + water_pressure * 0.018 + pathogen * 0.025) / disease_resistance
        if self._chance(disease_rate, hours, f"disease_start_{animal['id']}"):
            disease, details = self._select_disease(animal, nitrogen_pressure, dirty_pressure, salinity_pressure, injury_pressure, acclimation_pressure)
            animal["disease"] = disease
            animal["last_random_event"] = disease
            self._random_note(f"{animal['name']} developed {disease}")
            self._record("warning", f"{animal['name']} looks ill", details, animal["id"])

    def _select_disease(self, animal: dict[str, Any], nitrogen_pressure: float, dirty_pressure: float, salinity_pressure: float, injury_pressure: float, acclimation_pressure: float) -> tuple[str, str]:
        water = self.state["water"]
        if nitrogen_pressure > 0.5 or water.get("chlorine_mg_l", 0.0) + water.get("chloramine_mg_l", 0.0) > 0.03:
            return "gill inflammation", "Poor nitrogen control or disinfectant exposure irritated the gills and opened the door to infection."
        if injury_pressure > 0.28 and dirty_pressure > 0.12:
            return "fin rot", "Damaged fins plus dirty water allowed bacterial fin rot to start."
        if injury_pressure > 0.22 and water.get("turbidity", 0.0) > 0.45:
            return "fungal wound infection", "A wound stayed dirty long enough for a cottony fungal infection to take hold."
        if water.get("system") == "saltwater" and (salinity_pressure > 0.32 or acclimation_pressure > 0.0):
            return "marine parasite outbreak", "Salinity or transfer stress allowed a marine parasite outbreak to appear."
        if acclimation_pressure > 0.0 or float(animal.get("latent_pathogen_load", 0.0)) > 0.06:
            return "ich outbreak", "Transport or acclimation stress allowed latent white-spot style parasites to break out."
        if dirty_pressure > 0.18:
            return "bacterial infection", "Organic waste and cloudy water created conditions for a bacterial infection."
        return "opportunistic infection", "Chronic stress, immune weakness, or dirty water allowed an opportunistic infection to appear."

    def _update_animal(self, animal: dict[str, Any], groups: dict[str, int], welfare: dict[str, Any], consumed: float, hours: float) -> None:
        spec = self.species[animal["species_id"]]
        water = self.state["water"]
        aquarium = self.state["aquarium"]
        animal["age_days"] += hours / 24
        animal["hunger"] = clamp(animal["hunger"] + hours * 0.018, 0, 1)
        if consumed > 0 and animal["hunger"] > 0.18:
            meal_strength = clamp(consumed / max(0.015, float(spec.get("bioload", 0.5)) * 0.018), 0.15, 1.4)
            animal["hunger"] = clamp(animal["hunger"] - hours * 0.055 * meal_strength, 0, 1)
            animal["energy"] = clamp(animal["energy"] + hours * 0.025 * meal_strength, 0, 1)

        temp_stress = range_stress(water["temperature_c"], spec["temperature_c"]["ideal"], spec["temperature_c"]["tolerated"])
        ph_stress = range_stress(water["ph"], spec["ph"]["ideal"], spec["ph"]["tolerated"])
        hardness_stress = range_stress(water["gh_dgh"], spec["gh_dgh"]["ideal"], spec["gh_dgh"]["tolerated"])
        salinity_stress = range_stress(water.get("salinity_ppt", 0.2), spec.get("salinity_ppt", {"ideal": [0, 1], "tolerated": [0, 2]})["ideal"], spec.get("salinity_ppt", {"ideal": [0, 1], "tolerated": [0, 2]})["tolerated"])
        system_stress = 1.0 if spec.get("water_type", "freshwater") != water.get("system", "freshwater") else 0.0
        oxygen_stress = clamp((spec["oxygen_min_mg_l"] - water["oxygen_mg_l"]) / max(1, spec["oxygen_min_mg_l"]), 0, 1)
        co2_stress = clamp((water.get("co2_mg_l", 4.0) - 18.0) / 18.0 + water.get("surface_film", 0.0) * 0.18, 0, 1)
        nitrogen_stress = clamp(water["ammonia_mg_l"] * 4 + water["nitrite_mg_l"] * 3 + max(0, water["nitrate_mg_l"] - spec["nitrate_warning_mg_l"]) / 40, 0, 1)
        volume_stress = clamp((spec["minimum_litres"] - aquarium["effective_litres"]) / spec["minimum_litres"], 0, 1)
        length_stress = clamp((spec["minimum_tank_length_cm"] - aquarium["length_cm"]) / spec["minimum_tank_length_cm"], 0, 1)
        group = groups[animal["species_id"]]
        social_stress = clamp((spec["minimum_group"] - group) / max(1, spec["minimum_group"]), 0, 1)
        animal["social_satisfaction"] = 1.0 - social_stress
        welfare_risk = welfare.get("animal_risks", {}).get(animal["id"], {})
        welfare_stress = float(welfare_risk.get("stress", 0.0))
        animal["welfare_reasons"] = welfare_risk.get("reasons", [])
        stress_target = max(temp_stress, ph_stress, hardness_stress, salinity_stress, system_stress, oxygen_stress, co2_stress, nitrogen_stress, volume_stress, length_stress, social_stress, welfare_stress)
        stress_target = clamp(stress_target * float(animal.get("stress_sensitivity", 1.0)), 0, 1)
        animal["acute_stress"] = clamp(animal["acute_stress"] + (stress_target - animal["acute_stress"]) * min(1, hours * 0.3), 0, 1)
        animal["chronic_stress"] = clamp(animal["chronic_stress"] + (animal["acute_stress"] - 0.2) * hours * 0.012, 0, 1)
        animal["fear_memory"] = clamp(float(animal.get("fear_memory", 0.0)) + max(0.0, animal["acute_stress"] - 0.42) * hours * 0.02 - hours * 0.004 * float(animal.get("boldness", 0.5)), 0, 1)
        animal["immune_condition"] = clamp(animal["immune_condition"] - animal["chronic_stress"] * hours * 0.004 / max(0.35, float(animal.get("disease_resistance", 1.0))) + hours * 0.0004, 0, 1)
        damage = max(0, nitrogen_stress - 0.35) * hours * 0.05 + max(0, oxygen_stress - 0.45) * hours * 0.06 + max(0, co2_stress - 0.55) * hours * 0.035
        damage += float(welfare_risk.get("damage_per_hour", 0.0)) * hours
        injury_pressure = float(welfare_risk.get("injury_per_hour", 0.0))
        if injury_pressure > 0:
            animal["injury"] = clamp(float(animal.get("injury", 0.0)) + injury_pressure * hours, 0, 1)
        animal["injury"] = clamp(float(animal.get("injury", 0.0)) - max(0.0, 0.75 - animal["chronic_stress"]) * hours * 0.0015, 0, 1)
        damage += float(animal.get("injury", 0.0)) * hours * 0.01
        damage *= clamp(1.0 + (1.0 - float(animal.get("genetic_resilience", 1.0))) * 0.45, 0.82, 1.12)
        if animal.get("disease"):
            disease_damage = (0.004 + animal["chronic_stress"] * 0.018 + max(0.0, 0.7 - animal["immune_condition"]) * 0.03) * hours
            damage += disease_damage / max(0.25, float(animal.get("disease_resistance", 1.0)))
        if animal["hunger"] > 0.9:
            damage += (animal["hunger"] - 0.9) * hours * 0.02
        animal["health"] = clamp(animal["health"] - damage + (1 - stress_target) * hours * 0.0008, 0, 1)
        animal["energy"] = clamp(animal["energy"] - (0.006 + animal["acute_stress"] * 0.012) * hours, 0, 1)
        animal["spawn_cooldown_days"] = max(0.0, float(animal.get("spawn_cooldown_days", 30.0)) - hours / 24.0)
        breeding_target = 1.0 if stress_target < 0.16 and animal["hunger"] < 0.45 and animal["health"] > 0.78 and group >= max(1, int(spec.get("minimum_group", 1))) else 0.0
        animal["breeding_condition"] = clamp(float(animal.get("breeding_condition", 0.0)) + (breeding_target - float(animal.get("breeding_condition", 0.0))) * min(1.0, hours * 0.035), 0, 1)
        local_hour = (datetime.now().hour + datetime.now().minute / 60.0 + float(animal.get("circadian_offset", 0.0))) % 24.0
        resting = local_hour < 6.0 or local_hour > 21.5
        if resting:
            animal["energy"] = clamp(animal["energy"] + hours * 0.018, 0, 1)

        if animal.get("disease"):
            animal["behavior"] = "hiding with signs of illness"
            animal["routine"] = "hide"
        elif oxygen_stress > 0.45:
            animal["behavior"] = "gasping at the surface"
            animal["routine"] = "surface"
        elif nitrogen_stress > 0.35:
            animal["behavior"] = "lethargic with rapid gill movement"
            animal["routine"] = "hide"
        elif float(animal.get("injury", 0.0)) > 0.25:
            animal["behavior"] = "keeping distance with minor injuries"
            animal["routine"] = "hide"
        elif float(animal.get("fear_memory", 0.0)) > 0.62 and float(animal.get("boldness", 0.5)) < 0.62:
            animal["behavior"] = "hesitating near a trusted hiding route"
            animal["routine"] = "hide"
        elif welfare_risk.get("reasons"):
            reason = str(welfare_risk["reasons"][0])
            if "undersized" in reason:
                animal["behavior"] = "panicked without a proper school"
                animal["routine"] = "scan"
            elif "aggression" in reason or "conflict" in reason:
                animal["behavior"] = "dodging aggression"
                animal["routine"] = "flee"
            elif "outcompeted" in reason:
                animal["behavior"] = "missing food and hanging back"
                animal["routine"] = "hang_back"
            elif "hiding" in reason:
                animal["behavior"] = "searching for cover"
                animal["routine"] = "hide"
            elif "open swimming" in reason:
                animal["behavior"] = "pacing for swimming room"
                animal["routine"] = "pace"
            else:
                animal["behavior"] = "showing welfare stress"
                animal["routine"] = "stress"
        elif social_stress > 0.3:
            animal["behavior"] = "hiding and scanning for companions"
            animal["routine"] = "scan"
        elif resting:
            animal["behavior"] = "resting near cover"
            animal["routine"] = "rest"
        elif animal["hunger"] > 0.72:
            animal["behavior"] = "searching for food"
            animal["routine"] = "forage"
        elif float(animal.get("breeding_condition", 0.0)) > 0.78:
            animal["behavior"] = "displaying breeding condition"
            animal["routine"] = "display"
        elif spec["swim_zone"] == "bottom":
            animal["behavior"] = "foraging over the substrate"
            animal["routine"] = "forage"
        elif spec["social"] == "schooling":
            animal["behavior"] = "schooling"
            animal["routine"] = "school"
        elif float(animal.get("curiosity", 0.5)) > 0.72 and animal["acute_stress"] < 0.16:
            animal["behavior"] = "curiously inspecting the scape"
            animal["routine"] = "inspect"
        else:
            animal["behavior"] = "patrolling planted cover"
            animal["routine"] = "patrol"

        if animal["health"] <= 0:
            animal["alive"] = False
            animal["cause_of_death"] = self._cause_of_death(animal, oxygen_stress, nitrogen_stress)
            self._apply_death_load(animal)
            self._record("critical", f"{animal['name']} died", animal["cause_of_death"], animal["id"])

    def _cause_of_death(self, animal: dict[str, Any], oxygen_stress: float, nitrogen_stress: float) -> str:
        reasons = " ".join(str(reason) for reason in animal.get("welfare_reasons", []))
        if animal.get("disease"):
            return f"Primary cause: {animal['disease']}. The disease was enabled by sustained stress, immune decline, or degraded water rather than a random instant death."
        if "undersized" in reasons:
            return "Primary cause: severe social deprivation. This schooling or shoaling animal was kept below its minimum group size long enough to collapse from chronic stress."
        if "aggression" in reasons or "conflict" in reasons:
            return "Primary cause: social aggression. Territorial or community pressure caused sustained stress and injury risk."
        if nitrogen_stress > 0.6:
            return "Primary cause: nitrogen toxicity. Contributing evidence includes elevated ammonia or nitrite and prolonged respiratory stress."
        if oxygen_stress > 0.6:
            return "Primary cause: oxygen deprivation. The animal showed sustained oxygen stress before death."
        if animal["hunger"] > 0.95:
            return "Primary cause: prolonged starvation. Feeding history showed severe unresolved hunger."
        return "Primary cause: cumulative chronic stress and declining immune condition. Inspect recent water and social history."

    def _check_emergencies(self) -> None:
        water = self.state["water"]
        if water["ammonia_mg_l"] > 0.25:
            self._record_once("ammonia", "critical", "Ammonia is dangerous", f"Ammonia reached {water['ammonia_mg_l']:.2f} mg/L. Stop feeding, test the filter, and perform an appropriate partial water change.")
        if water["nitrite_mg_l"] > 0.25:
            self._record_once("nitrite", "critical", "Nitrite is dangerous", f"Nitrite reached {water['nitrite_mg_l']:.2f} mg/L and is impairing oxygen transport.")
        if water["oxygen_mg_l"] < 4.5:
            self._record_once("oxygen", "critical", "Dissolved oxygen is low", f"Oxygen fell to {water['oxygen_mg_l']:.1f} mg/L. Increase aeration and inspect filtration.")
        if water["nitrate_mg_l"] > 30:
            self._record_once("nitrate", "warning", "Nitrate is accumulating", f"Nitrate reached {water['nitrate_mg_l']:.0f} mg/L. Plan a partial water change.")
        if water.get("chlorine_mg_l", 0.0) > 0.02 or water.get("chloramine_mg_l", 0.0) > 0.02:
            self._record_once("chlorine", "critical", "Untreated water is dangerous", "Chlorine or chloramine was detected. Always dechlorinate replacement water.")
        if water.get("co2_mg_l", 0.0) > 20.0:
            self._record_once("co2", "warning", "CO2 is high", f"CO2 reached {water.get('co2_mg_l', 0.0):.0f} mg/L. Increase gas exchange and check surface film.")
        if water.get("surface_film", 0.0) > 0.55:
            self._record_once("surface_film", "warning", "Surface film is building", "Protein/oil film is reducing gas exchange. Remove film and increase surface movement.")
        if water.get("detritus", 0.0) > 0.65:
            self._record_once("detritus", "warning", "Detritus is building up", "Mulm and debris in the substrate are feeding long-term nitrate, phosphate, and oxygen demand.")
        if water.get("water_level", 1.0) < 0.93:
            self._record_once("low_water_level", "warning", "Water level has dropped", "Evaporation is concentrating minerals. Top off with fresh water, especially in saltwater.")
        if water.get("system") == "saltwater" and not (33.0 <= water.get("salinity_ppt", 35.0) <= 37.0):
            self._record_once("salinity_drift", "warning", "Salinity is drifting", f"Salinity is {water.get('salinity_ppt', 35.0):.1f} ppt. Correct slowly with top-off or properly mixed saltwater.")
        skimmer = self.state.get("equipment", {}).get("protein_skimmer", {})
        if water.get("system") == "saltwater" and skimmer.get("enabled", False) and float(skimmer.get("cup_fullness", 0.0)) > 0.88:
            self._record_once("skimmer_cup", "warning", "Skimmer cup needs emptying", "The protein skimmer is losing export efficiency.")
        if self.state["biology"].get("algae", 0.0) > 0.55:
            self._record_once("algae", "warning", "Algae pressure is high", "Reduce light, avoid direct sun, control phosphate/nitrate, and avoid overfeeding.")
        if not self.state.get("cycle", {}).get("ready_for_animals", True):
            self._record_once("cycle_not_ready", "warning", "Cycle is not ready", "Wait for ammonia and nitrite to reach zero before adding animals.")
        for issue in self.state.get("planning", {}).get("issues", [])[:3]:
            self._record_once(f"planning_{issue.get('title', 'issue')}", issue.get("severity", "warning"), issue.get("title", "Planning issue"), issue.get("details", "Check tank placement and support."))
        for issue in self.state.get("maintenance", {}).get("issues", [])[:3]:
            self._record_once(f"maintenance_{issue.get('title', 'issue')}", issue.get("severity", "warning"), issue.get("title", "Maintenance issue"), issue.get("details", "Maintenance is overdue."))
        for issue in self.state.get("welfare", {}).get("issues", [])[:4]:
            self._record_once(f"welfare_{issue.get('key', issue.get('title', 'issue'))}", issue.get("severity", "warning"), issue.get("title", "Welfare issue"), issue.get("details", "The community has a welfare problem."))

    def _update_symptoms(self) -> None:
        water = self.state["water"]
        biology = self.state["biology"]
        maturity = self.state.get("maturity", {})
        animals = [a for a in self.state.get("animals", []) if a.get("alive", True)]
        plants = self.state.get("aquarium", {}).get("scape", {}).get("plants", [])
        corals = self.state.get("aquarium", {}).get("scape", {}).get("corals", [])
        objects = self.state.get("aquarium", {}).get("scape", {}).get("objects", [])
        coral_items = list(corals) + [obj for obj in objects if obj.get("category") == "corals"]
        plant_melt = max((1.0 - float(p.get("health", 0.8)) for p in plants), default=0.0)
        coral_stress = max((1.0 - float(c.get("health", 0.8)) for c in coral_items), default=0.0)
        gasping = sum(1 for a in animals if str(a.get("routine", "")) == "surface" or "rapid gill" in str(a.get("behavior", "")))
        hiding = sum(1 for a in animals if str(a.get("routine", "")) == "hiding" or "hiding" in str(a.get("behavior", "")))
        stressed = sum(1 for a in animals if float(a.get("acute_stress", 0.0)) > 0.45 or float(a.get("chronic_stress", 0.0)) > 0.35)
        self.state["symptoms"] = {
            "cloudiness": clamp(water.get("turbidity", 0.0) + water.get("organic_waste", 0.0) * 0.08, 0.0, 1.0),
            "green_water": clamp(float(biology.get("algae", 0.0)) * 0.85 + max(0.0, water.get("nitrate_mg_l", 0.0) - 25.0) * 0.006 + water.get("phosphate_mg_l", 0.0) * 0.16, 0.0, 1.0),
            "surface_film": clamp(water.get("surface_film", 0.0), 0.0, 1.0),
            "dirty_substrate": clamp(water.get("detritus", 0.0) + float(maturity.get("mulm", 0.0)) * 0.45, 0.0, 1.0),
            "glass_algae": clamp(float(maturity.get("glass_algae", 0.0)), 0.0, 1.0),
            "plant_melt": clamp(plant_melt, 0.0, 1.0),
            "coral_bleach": clamp(coral_stress, 0.0, 1.0),
            "gasping_animals": gasping,
            "hiding_animals": hiding,
            "stressed_animals": stressed,
        }

    def _record_once(self, key: str, severity: str, title: str, details: str) -> None:
        now = time.time()
        if now - self._event_keys.get(key, 0) < 1800:
            return
        self._event_keys[key] = now
        self._record(severity, title, details)

    def _record(self, severity: str, title: str, details: str, subject: str = "") -> None:
        self.state["events"].insert(0, event(severity, title, details, subject))
        self.state["events"] = self.state["events"][:80]

    def _summarize(self) -> None:
        living = [a for a in self.state["animals"] if a["alive"]]
        groups = self._groups(living)
        self._evaluate_planning()
        self._maintenance_status()
        self._update_cycle(0.0)
        welfare = self._community_welfare(living, groups)
        self.state["welfare"] = welfare
        self._update_symptoms()
        stressed = [a for a in living if a["acute_stress"] > 0.35 or a["chronic_stress"] > 0.3]
        water = self.state["water"]
        risks = []
        if water["ammonia_mg_l"] > 0.1:
            risks.append("ammonia")
        if water["nitrite_mg_l"] > 0.1:
            risks.append("nitrite")
        if water["oxygen_mg_l"] < 5:
            risks.append("low oxygen")
        if water["nitrate_mg_l"] > 25:
            risks.append("nitrate")
        if water.get("chlorine_mg_l", 0.0) > 0.02 or water.get("chloramine_mg_l", 0.0) > 0.02:
            risks.append("untreated water")
        if water.get("co2_mg_l", 0.0) > 18.0:
            risks.append("high CO2")
        if water.get("surface_film", 0.0) > 0.45:
            risks.append("surface film")
        if water.get("detritus", 0.0) > 0.6:
            risks.append("dirty substrate")
        if water.get("water_level", 1.0) < 0.95:
            risks.append("evaporation")
        if water.get("system") == "saltwater" and not (33.0 <= water.get("salinity_ppt", 35.0) <= 37.0):
            risks.append("salinity drift")
        if self.state["biology"].get("algae", 0.0) > 0.55:
            risks.append("algae pressure")
        if not self.state.get("cycle", {}).get("ready_for_animals", True):
            risks.append("cycle not ready")
        for issue in self.state.get("planning", {}).get("issues", [])[:2]:
            risks.append(issue["title"])
        for issue in self.state.get("maintenance", {}).get("issues", [])[:2]:
            risks.append(issue["title"])
        for issue in welfare.get("issues", [])[:3]:
            risks.append(issue["title"])
        self.state["summary"] = {
            "living_animals": len(living),
            "stressed_animals": len(stressed),
            "status": "critical" if welfare.get("status") == "critical" or any(e["severity"] == "critical" for e in self.state["events"][:3]) else "watch" if risks or stressed or welfare.get("status") == "watch" else "stable",
            "risks": risks,
            "welfare_score": welfare.get("score", 100),
            "last_updated": now_iso(),
        }
