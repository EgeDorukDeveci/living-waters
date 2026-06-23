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
    "branch_driftwood": {"name": "Branch driftwood", "hiding": 0.11, "soft_water": 0.025},
    "root_driftwood": {"name": "Root driftwood", "hiding": 0.16, "soft_water": 0.035},
    "live_rock": {"name": "Live rock", "system": "saltwater", "hiding": 0.18, "biofilter": 0.12, "algae_control": 0.035},
    "reef_arch": {"name": "Reef arch", "system": "saltwater", "hiding": 0.14, "biofilter": 0.08, "flow_break": 0.04},
}

CORAL_TYPES: dict[str, dict[str, Any]] = {
    "zoanthids": {"name": "Zoanthid colony", "nitrate_uptake": 0.035, "hiding": 0.04, "algae_control": 0.02, "maintenance": 0.025, "light_need": 0.55},
    "mushroom_coral": {"name": "Mushroom coral", "nitrate_uptake": 0.025, "hiding": 0.035, "algae_control": 0.015, "maintenance": 0.018, "light_need": 0.42},
    "green_star_polyps": {"name": "Green star polyps", "nitrate_uptake": 0.045, "hiding": 0.045, "algae_control": 0.02, "maintenance": 0.035, "light_need": 0.58},
    "torch_coral": {"name": "Torch coral", "nitrate_uptake": 0.02, "hiding": 0.06, "algae_control": 0.01, "maintenance": 0.06, "light_need": 0.72},
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
    fish: list[dict[str, Any]] = []
    for index in range(8):
        fish.append(make_animal(species["neon_tetra"], f"Neon {index + 1}", index))
    for index in range(6):
        fish.append(make_animal(species["peppered_cory"], f"Cory {index + 1}", 20 + index))
    for index in range(10):
        fish.append(make_animal(species["cherry_shrimp"], f"Shrimp {index + 1}", 40 + index))
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
            "ammonia_mg_l": 0.0,
            "nitrite_mg_l": 0.0,
            "nitrate_mg_l": 8.0,
            "organic_waste": 0.12,
            "turbidity": 0.08,
        },
        "biology": {
            "ammonia_bacteria": 0.86,
            "nitrite_bacteria": 0.84,
            "plant_health": 0.91,
            "algae": 0.12,
        },
        "equipment": {
            "filter": {"enabled": True, "health": 0.96, "flow": 0.78, "maturity": 0.9},
            "heater": {"enabled": True, "health": 0.98, "target_c": 23.5},
            "light": {"enabled": True, "health": 0.99, "hours_per_day": 8.0},
            "air_pump": {"enabled": True, "health": 0.97, "output": 0.5},
        },
        "animals": fish,
        "food": {"available": 0.0, "decaying": 0.0, "last_fed": now_iso()},
        "clock": {
            "simulated_at": now_iso(),
            "last_real_timestamp": time.time(),
            "total_simulated_seconds": 0.0,
            "speed": 1.0,
            "paused": False,
            "vacation_mode": False,
            "emergency_pause": False,
        },
        "events": [
            event("info", "Aquarium established", "The biofilter is mature and the initial inhabitants are stable.")
        ],
        "summary": {},
    }


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
    }


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
        water = self.state.setdefault("water", {})
        water.setdefault("system", "saltwater" if water.get("salinity_ppt", 0) > 5 else "freshwater")
        water.setdefault("salinity_ppt", 35.0 if water["system"] == "saltwater" else 0.2)
        water.setdefault("calcium_mg_l", 420.0 if water["system"] == "saltwater" else 35.0)
        water.setdefault("alkalinity_dkh", 8.2 if water["system"] == "saltwater" else water.get("kh_dkh", 4.0))
        scape = aquarium["scape"]
        scape.setdefault("rocks", [])
        scape.setdefault("wood", [])
        scape.setdefault("plants", [])
        scape.setdefault("corals", [])
        scape.setdefault("objects", [])
        scape.setdefault("layout_seed", 42)
        for animal in self.state.get("animals", []):
            animal.setdefault("acclimated", True)
            animal.setdefault("acclimation_minutes", self.species.get(animal.get("species_id", ""), {}).get("acclimation_minutes", 30))
            animal.setdefault("decomposition_hours", 0.0)
            animal.setdefault("death_load_remaining", 0.0 if animal.get("alive", True) else self.species.get(animal.get("species_id", ""), {}).get("bioload", 0.5) * 0.1)
        aquarium.update(self._scape_metrics())

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

    def water_change(self, fraction: float = 0.25) -> None:
        fraction = clamp(fraction, 0.05, 0.6)
        water = self.state["water"]
        for key in ("ammonia_mg_l", "nitrite_mg_l", "nitrate_mg_l", "organic_waste", "turbidity"):
            water[key] *= 1.0 - fraction
        water["temperature_c"] += (23.0 - water["temperature_c"]) * fraction * 0.35
        water["oxygen_mg_l"] = clamp(water["oxygen_mg_l"] + fraction * 1.2, 0, 10)
        self._record("info", "Partial water change", f"{fraction * 100:.0f}% of the water was replaced gradually.")

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
            })
            self.add_animal("ocellaris_clownfish", acclimation_minutes=45, name="Clown 1")
            self.add_animal("ocellaris_clownfish", acclimation_minutes=45, name="Clown 2")
            self.add_animal("royal_gramma", acclimation_minutes=45, name="Gramma 1")
            self._record("info", "Saltwater reef started", "The tank was converted to a conservative starter reef. Freshwater animals were not carried over.")
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
        return {
            "plant_cover": clamp(nitrate_uptake / 4.2, 0.05, 0.96),
            "hiding_cover": clamp(hiding / 3.6, 0.05, 0.96),
            "nitrate_uptake": clamp(nitrate_uptake / 5.0, 0.02, 1.3),
            "oxygen_day": clamp(oxygen_day / 5.0, 0.0, 0.9),
            "oxygen_night": clamp(oxygen_night / 5.0, -0.5, 0.0),
            "algae_control": clamp(algae_control / 2.8, 0.0, 0.85),
            "maintenance_load": clamp(maintenance / 2.5, 0.0, 0.55),
            "surface_shade": clamp(surface_shade / 2.0, 0.0, 0.65),
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

    def _tick(self, seconds: float) -> None:
        hours = seconds / 3600.0
        water = self.state["water"]
        bio = self.state["biology"]
        equipment = self.state["equipment"]
        food = self.state["food"]
        self.state["aquarium"].update(self._scape_metrics())
        scape_metrics = self.state["aquarium"]
        self._decompose_dead_animals(hours)
        living = [a for a in self.state["animals"] if a["alive"]]
        total_bioload = sum(self.species[a["species_id"]]["bioload"] for a in living)

        consumed = min(food["available"], sum(max(0.0, a["hunger"] - 0.2) for a in living) * hours * 0.32)
        food["available"] -= consumed
        food["decaying"] += max(0.0, food["available"] - 0.12) * hours * 0.06
        waste_input = (total_bioload * 0.0015 + food["decaying"] * 0.035) * hours
        water["organic_waste"] = clamp(water["organic_waste"] + waste_input * 0.7 + scape_metrics["maintenance_load"] * hours * 0.0015, 0, 5)
        water["ammonia_mg_l"] += waste_input

        filter_state = equipment["filter"]
        filter_factor = (
            float(filter_state["enabled"])
            * filter_state["health"]
            * filter_state["flow"]
            * filter_state["maturity"]
        )
        oxygen_factor = clamp(water["oxygen_mg_l"] / 7.0, 0.1, 1.2)
        ammonia_conversion = min(
            water["ammonia_mg_l"],
            bio["ammonia_bacteria"] * filter_factor * oxygen_factor * hours * 0.045,
        )
        water["ammonia_mg_l"] -= ammonia_conversion
        water["nitrite_mg_l"] += ammonia_conversion
        nitrite_conversion = min(
            water["nitrite_mg_l"],
            bio["nitrite_bacteria"] * filter_factor * oxygen_factor * hours * 0.04,
        )
        water["nitrite_mg_l"] -= nitrite_conversion
        water["nitrate_mg_l"] += nitrite_conversion

        bacterial_food = clamp((water["ammonia_mg_l"] + water["nitrite_mg_l"]) * 2.0, 0, 1)
        bio["ammonia_bacteria"] = clamp(bio["ammonia_bacteria"] + (bacterial_food - 0.2) * hours * 0.002, 0.05, 1)
        bio["nitrite_bacteria"] = clamp(bio["nitrite_bacteria"] + (bacterial_food - 0.2) * hours * 0.0018, 0.05, 1)
        plant_uptake = bio["plant_health"] * scape_metrics["nitrate_uptake"] * hours * 0.015
        water["nitrate_mg_l"] = max(0.0, water["nitrate_mg_l"] - plant_uptake)

        hour = datetime.now().hour
        lights_on = 10 <= hour < 18 and equipment["light"]["enabled"]
        oxygen_gain = (
            self.state["aquarium"]["surface_agitation"] * 0.18
            + equipment["air_pump"]["enabled"] * equipment["air_pump"]["output"] * 0.17
            + bio["plant_health"] * (scape_metrics["oxygen_day"] if lights_on else scape_metrics["oxygen_night"])
        )
        oxygen_use = total_bioload * 0.008 + water["organic_waste"] * 0.018
        water["oxygen_mg_l"] = clamp(water["oxygen_mg_l"] + (oxygen_gain - oxygen_use) * hours, 0, 10)

        heater = equipment["heater"]
        ambient = 21.0
        target = heater["target_c"] if heater["enabled"] and heater["health"] > 0.15 else ambient
        water["temperature_c"] += (target - water["temperature_c"]) * min(1.0, hours * 0.12)
        water["turbidity"] = clamp(water["turbidity"] + water["organic_waste"] * hours * 0.002 - filter_factor * hours * 0.01, 0, 1)
        water["ph"] = clamp(water["ph"] - water["organic_waste"] * hours * 0.00025 + (water["kh_dkh"] - 4) * hours * 0.0001, 4.5, 9)
        bio["algae"] = clamp(
            bio["algae"]
            + (0.005 if lights_on else -0.001) * hours
            + water["nitrate_mg_l"] * hours * 0.00005
            - scape_metrics["algae_control"] * hours * 0.002,
            0,
            1,
        )
        self._update_corals(hours)

        groups = {}
        for animal in living:
            groups[animal["species_id"]] = groups.get(animal["species_id"], 0) + 1
        for animal in living:
            self._update_animal(animal, groups, consumed, hours)

        for item in equipment.values():
            item["health"] = clamp(item["health"] - hours * 0.00002, 0, 1)
        filter_state["flow"] = clamp(filter_state["flow"] - water["organic_waste"] * hours * 0.00008, 0.08, 1)
        self._check_emergencies()

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
            water["turbidity"] = clamp(water["turbidity"] + release * 0.08, 0, 1)

    def _apply_death_load(self, animal: dict[str, Any], immediate: bool = False) -> None:
        spec = self.species.get(animal.get("species_id", ""), {})
        load = spec.get("bioload", 0.6) * (0.28 if immediate else 0.18)
        animal["death_load_remaining"] = float(animal.get("death_load_remaining", 0.0)) + load
        animal["decomposition_hours"] = 0.0
        if immediate:
            water = self.state["water"]
            water["ammonia_mg_l"] += load * 0.25
            water["organic_waste"] = clamp(water["organic_waste"] + load * 0.35, 0, 5)
            water["turbidity"] = clamp(water["turbidity"] + load * 0.04, 0, 1)

    def _update_corals(self, hours: float) -> None:
        if self.state["water"].get("system") != "saltwater":
            return
        water = self.state["water"]
        temp_stress = range_stress(water["temperature_c"], [24.0, 26.5], [22.5, 29.0])
        salinity_stress = range_stress(water.get("salinity_ppt", 35.0), [34.0, 36.0], [31.0, 38.0])
        nitrate_stress = clamp((water["nitrate_mg_l"] - 15.0) / 35.0, 0, 1)
        stress = max(temp_stress, salinity_stress, nitrate_stress)
        if stress <= 0.02:
            return
        for coral in self.state["aquarium"]["scape"].get("corals", []):
            coral["health"] = clamp(float(coral.get("health", 0.8)) - stress * hours * 0.012, 0, 1)
        for obj in self.state["aquarium"]["scape"].get("objects", []):
            if obj.get("category") == "corals":
                obj["health"] = clamp(float(obj.get("health", 0.8)) - stress * hours * 0.012, 0, 1)
        if stress > 0.45:
            self._record_once("coral_stress", "warning", "Corals are stressed", "Temperature, salinity, or nitrate is outside the reef comfort range.")

    def _update_animal(self, animal: dict[str, Any], groups: dict[str, int], consumed: float, hours: float) -> None:
        spec = self.species[animal["species_id"]]
        water = self.state["water"]
        aquarium = self.state["aquarium"]
        animal["age_days"] += hours / 24
        animal["hunger"] = clamp(animal["hunger"] + hours * 0.018, 0, 1)
        if consumed > 0 and animal["hunger"] > 0.18:
            animal["hunger"] = clamp(animal["hunger"] - hours * 0.09, 0, 1)
            animal["energy"] = clamp(animal["energy"] + hours * 0.04, 0, 1)

        temp_stress = range_stress(water["temperature_c"], spec["temperature_c"]["ideal"], spec["temperature_c"]["tolerated"])
        ph_stress = range_stress(water["ph"], spec["ph"]["ideal"], spec["ph"]["tolerated"])
        hardness_stress = range_stress(water["gh_dgh"], spec["gh_dgh"]["ideal"], spec["gh_dgh"]["tolerated"])
        salinity_stress = range_stress(water.get("salinity_ppt", 0.2), spec.get("salinity_ppt", {"ideal": [0, 1], "tolerated": [0, 2]})["ideal"], spec.get("salinity_ppt", {"ideal": [0, 1], "tolerated": [0, 2]})["tolerated"])
        system_stress = 1.0 if spec.get("water_type", "freshwater") != water.get("system", "freshwater") else 0.0
        oxygen_stress = clamp((spec["oxygen_min_mg_l"] - water["oxygen_mg_l"]) / max(1, spec["oxygen_min_mg_l"]), 0, 1)
        nitrogen_stress = clamp(water["ammonia_mg_l"] * 4 + water["nitrite_mg_l"] * 3 + max(0, water["nitrate_mg_l"] - spec["nitrate_warning_mg_l"]) / 40, 0, 1)
        volume_stress = clamp((spec["minimum_litres"] - aquarium["effective_litres"]) / spec["minimum_litres"], 0, 1)
        length_stress = clamp((spec["minimum_tank_length_cm"] - aquarium["length_cm"]) / spec["minimum_tank_length_cm"], 0, 1)
        group = groups[animal["species_id"]]
        social_stress = clamp((spec["minimum_group"] - group) / max(1, spec["minimum_group"]), 0, 1)
        animal["social_satisfaction"] = 1.0 - social_stress
        stress_target = max(temp_stress, ph_stress, hardness_stress, salinity_stress, system_stress, oxygen_stress, nitrogen_stress, volume_stress, length_stress, social_stress)
        animal["acute_stress"] = clamp(animal["acute_stress"] + (stress_target - animal["acute_stress"]) * min(1, hours * 0.3), 0, 1)
        animal["chronic_stress"] = clamp(animal["chronic_stress"] + (animal["acute_stress"] - 0.2) * hours * 0.012, 0, 1)
        animal["immune_condition"] = clamp(animal["immune_condition"] - animal["chronic_stress"] * hours * 0.004 + hours * 0.0004, 0, 1)
        damage = max(0, nitrogen_stress - 0.35) * hours * 0.05 + max(0, oxygen_stress - 0.45) * hours * 0.06
        if animal["hunger"] > 0.9:
            damage += (animal["hunger"] - 0.9) * hours * 0.02
        animal["health"] = clamp(animal["health"] - damage + (1 - stress_target) * hours * 0.0008, 0, 1)
        animal["energy"] = clamp(animal["energy"] - (0.006 + animal["acute_stress"] * 0.012) * hours, 0, 1)

        if oxygen_stress > 0.45:
            animal["behavior"] = "gasping at the surface"
        elif nitrogen_stress > 0.35:
            animal["behavior"] = "lethargic with rapid gill movement"
        elif social_stress > 0.3:
            animal["behavior"] = "hiding and scanning for companions"
        elif animal["hunger"] > 0.72:
            animal["behavior"] = "searching for food"
        elif spec["swim_zone"] == "bottom":
            animal["behavior"] = "foraging over the substrate"
        elif spec["social"] == "schooling":
            animal["behavior"] = "schooling"
        else:
            animal["behavior"] = "patrolling planted cover"

        if animal["health"] <= 0:
            animal["alive"] = False
            animal["cause_of_death"] = self._cause_of_death(animal, oxygen_stress, nitrogen_stress)
            self._apply_death_load(animal)
            self._record("critical", f"{animal['name']} died", animal["cause_of_death"], animal["id"])

    def _cause_of_death(self, animal: dict[str, Any], oxygen_stress: float, nitrogen_stress: float) -> str:
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
        self.state["summary"] = {
            "living_animals": len(living),
            "stressed_animals": len(stressed),
            "status": "critical" if any(e["severity"] == "critical" for e in self.state["events"][:3]) else "watch" if risks or stressed else "stable",
            "risks": risks,
            "last_updated": now_iso(),
        }
