from __future__ import annotations

import argparse
import ctypes
import json
import os
import subprocess
import sys
import threading
import time
import winreg
from pathlib import Path
from typing import Any

import pystray
from PIL import Image, ImageDraw
from win11toast import notify

from simulation import AquariumSimulation, default_state, load_species, make_animal, now_iso


APP_NAME = "Living Waters"
MUTEX_NAME = "Local\\Living_Waters_Background"
FROZEN = bool(getattr(sys, "frozen", False))
ROOT = Path(os.environ.get("LIVING_WATERS_ROOT", Path(sys.executable).resolve().parent if FROZEN else Path(__file__).resolve().parents[1]))
RUNTIME = ROOT / "runtime"
STATE_PATH = RUNTIME / "aquarium_state.json"
COMMAND_PATH = RUNTIME / "command.json"
SPECIES_PATH = ROOT / "data" / "species" / "freshwater_v1.json"
LOG_PATH = RUNTIME / "background.log"


def atomic_write(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, indent=2, ensure_ascii=True), encoding="utf-8")
    os.replace(temp, path)


def log(message: str) -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a", encoding="utf-8") as handle:
        handle.write(f"{now_iso()} {message}\n")


def load_state(species: dict[str, dict[str, Any]]) -> dict[str, Any]:
    if not STATE_PATH.exists():
        return default_state(species)
    try:
        return json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        backup = STATE_PATH.with_name(f"corrupt-{int(time.time())}.json")
        STATE_PATH.replace(backup)
        return default_state(species)


def app_icon() -> Image.Image:
    image = Image.new("RGBA", (64, 64), "#0b171b")
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((5, 8, 59, 56), radius=12, fill="#12313a", outline="#63d5c8", width=3)
    draw.ellipse((16, 24, 42, 41), fill="#63d5c8")
    draw.polygon([(39, 24), (54, 18), (52, 38)], fill="#63d5c8")
    draw.ellipse((22, 29, 25, 32), fill="#0b171b")
    draw.line((10, 48, 54, 48), fill="#8cb86b", width=3)
    return image


class SingleInstance:
    def __init__(self) -> None:
        self.handle = ctypes.windll.kernel32.CreateMutexW(None, False, MUTEX_NAME)
        self.already_exists = ctypes.windll.kernel32.GetLastError() == 183

    def close(self) -> None:
        if self.handle:
            ctypes.windll.kernel32.CloseHandle(self.handle)


class Daemon:
    def __init__(self, diagnostic: bool = False) -> None:
        self.diagnostic = diagnostic
        self.species = load_species(SPECIES_PATH)
        self.state = load_state(self.species)
        self.sim = AquariumSimulation(self.species, self.state)
        self.stop_event = threading.Event()
        self.last_notified_event = ""
        self.icon: pystray.Icon | None = None

    def start(self) -> None:
        last_real = float(self.state["clock"].get("last_real_timestamp", time.time()))
        offline = min(max(0, time.time() - last_real), 12 * 60 * 60)
        if offline > 60:
            self.sim.advance(offline, offline=True)
            self.state["events"].insert(
                0,
                {
                    "id": f"offline-{int(time.time())}",
                    "timestamp": now_iso(),
                    "severity": "info",
                    "title": "Background time restored",
                    "details": f"{offline / 3600:.1f} hours were simulated safely after the process was unavailable.",
                    "subject": ""
                },
            )
        atomic_write(STATE_PATH, self.state)
        threading.Thread(target=self._loop, name="living-waters-simulation", daemon=True).start()
        menu = pystray.Menu(
            pystray.MenuItem("Open aquarium", lambda *_: self.open_game(), default=True),
            pystray.MenuItem("Feed modestly", lambda *_: self.command("feed")),
            pystray.MenuItem("Pause ecosystem", lambda *_: self.command("toggle_pause")),
            pystray.MenuItem("Test notification", lambda *_: self.test_notification()),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Exit background simulation", lambda *_: self.stop()),
        )
        self.icon = pystray.Icon("living_waters", app_icon(), APP_NAME, menu)
        self.icon.run()

    def _loop(self) -> None:
        previous = time.time()
        while not self.stop_event.wait(5):
            current = time.time()
            elapsed = current - previous
            previous = current
            try:
                self._handle_command()
                self.sim.advance(elapsed)
                atomic_write(STATE_PATH, self.state)
                self._notify_important_event()
            except Exception as exc:
                log(f"simulation-error {exc}")

    def _handle_command(self) -> None:
        if not COMMAND_PATH.exists():
            return
        try:
            command = json.loads(COMMAND_PATH.read_text(encoding="utf-8"))
        finally:
            COMMAND_PATH.unlink(missing_ok=True)
        action = command.get("action")
        if action == "feed":
            self.sim.feed(float(command.get("amount", 0.42)))
        elif action == "water_change":
            self.sim.water_change(float(command.get("fraction", 0.25)), bool(command.get("conditioner_used", True)))
        elif action == "weekly_maintenance":
            self.sim.weekly_maintenance()
        elif action == "service_filter":
            self.sim.service_filter(bool(command.get("replace_carbon", True)))
        elif action == "dose_ammonia":
            self.sim.dose_ammonia(float(command.get("amount", 1.0)))
        elif action == "test_water":
            self.sim.test_water()
        elif action == "toggle_pause":
            self.state["clock"]["paused"] = not self.state["clock"]["paused"]
        elif action == "set_speed":
            self.state["clock"]["speed"] = max(0.0, min(10.0, float(command.get("speed", 1))))
        elif action == "add_scape_item":
            self.sim.add_scape_item(
                str(command.get("category", "")),
                str(command.get("type", "")),
                int(command.get("quantity", 1)),
            )
        elif action == "reset_scape":
            self.sim.reset_scape()
        elif action == "switch_system":
            self.sim.switch_system(str(command.get("system", "freshwater")))
        elif action == "add_animal":
            self.sim.add_animal(
                str(command.get("species_id", "")),
                int(command.get("acclimation_minutes", 30)),
                str(command.get("name", "")),
            )
        elif action == "remove_animal":
            self.sim.remove_animal(str(command.get("animal_id", "")))
        elif action == "place_scape_item":
            self.sim.place_scape_item(
                str(command.get("category", "")),
                str(command.get("type", "")),
                float(command.get("x", 0.5)),
                float(command.get("y", 0.8)),
                float(command.get("scale", 1.0)),
            )
        elif action == "move_scape_item":
            self.sim.move_scape_item(
                str(command.get("object_id", "")),
                float(command.get("x", 0.5)),
                float(command.get("y", 0.8)),
            )
        elif action == "remove_scape_item":
            self.sim.remove_scape_item(str(command.get("object_id", "")))

    def command(self, action: str) -> None:
        atomic_write(COMMAND_PATH, {"action": action, "timestamp": now_iso()})

    def _notify_important_event(self) -> None:
        if not self.state["events"]:
            return
        item = self.state["events"][0]
        if item["id"] == self.last_notified_event or item["severity"] not in {"warning", "critical"}:
            return
        self.last_notified_event = item["id"]
        if self.diagnostic:
            return
        try:
            notify(item["title"], item["details"], app_id=APP_NAME, audio={"silent": "true"})
        except Exception as exc:
            log(f"notification-error {exc}")

    def test_notification(self) -> None:
        if self.diagnostic:
            return
        notify(
            "Living Waters is alive",
            "The aquarium continues simulating while its window is closed.",
            app_id=APP_NAME,
            audio={"silent": "true"},
        )

    def open_game(self) -> None:
        exe = ROOT / "Living Waters.exe"
        if exe.exists():
            subprocess.Popen([str(exe)], cwd=ROOT)
            return
        godot = ROOT / "tools" / "godot" / "Godot_v4.7-stable_win64.exe"
        if godot.exists():
            subprocess.Popen([str(godot), "--path", str(ROOT)], cwd=ROOT)

    def stop(self) -> None:
        self.stop_event.set()
        atomic_write(STATE_PATH, self.state)
        if self.icon:
            self.icon.stop()


def register_startup(enabled: bool = True) -> None:
    key_path = r"Software\Microsoft\Windows\CurrentVersion\Run"
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, key_path) as key:
        if enabled:
            command = f'"{sys.executable}" --background' if FROZEN else f'"{Path(sys.executable).with_name("pythonw.exe")}" "{Path(__file__).resolve()}" --background'
            winreg.SetValueEx(key, APP_NAME, 0, winreg.REG_SZ, command)
        else:
            try:
                winreg.DeleteValue(key, APP_NAME)
            except FileNotFoundError:
                pass


def self_test() -> int:
    species = load_species(SPECIES_PATH)
    state = default_state(species)
    for index in range(6):
        state["animals"].append(make_animal(species["neon_tetra"], f"Neon {index + 1}", index))
    sim = AquariumSimulation(species, state)
    initial_nitrate = state["water"]["nitrate_mg_l"]
    sim.feed(0.8)
    sim.advance(6 * 3600)
    assert state["food"]["available"] < 0.8
    assert state["clock"]["total_simulated_seconds"] == 6 * 3600
    sim.water_change(0.25)
    assert state["water"]["nitrate_mg_l"] < initial_nitrate + 5
    sim.service_filter()
    assert state["equipment"]["filter"]["media"]["chemical"]["carbon_remaining"] > 0.9
    neon = next(a for a in state["animals"] if a["species_id"] == "neon_tetra")
    assert neon["social_satisfaction"] > 0.9
    state["water"]["ammonia_mg_l"] = 1.0
    sim.advance(3600)
    assert neon["acute_stress"] > 0.1
    print("Living Waters background self-test passed.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--background", action="store_true")
    parser.add_argument("--diagnostic", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--register-startup", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.register_startup:
        register_startup(True)
        return 0
    instance = SingleInstance()
    if instance.already_exists:
        return 0
    try:
        register_startup(True)
        Daemon(args.diagnostic).start()
    finally:
        instance.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
