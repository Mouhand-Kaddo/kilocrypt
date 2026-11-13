"""Run headless bot scenarios and fail when monsters idle, get stuck, or the player heals too fast.

Usage: python3 tools/linux-test/scenarios.py [GLSL] [--report FILE]

Each scenario renders at 320x180 with tools/linux-test/shot.sh and reads the bot log (one line per
second of game time). The bot sidesteps and dashes away from charging or lunging monsters. Exits 1 if any limit is broken. Scenarios run in parallel (JOBS, default 4). With
--report, a passing run writes FILE.stamp, a hash of the shader and these tools; a later run with the same
hash prints the saved report instead of running again.
"""
import concurrent.futures
import hashlib
import os
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SCENARIOS = [
    ("standing player, floor 2", "BOT STAND LEVEL=2.0", 5400),
    ("bot, floor 1", "BOT LEVEL=1.0", 3600),
    ("bot, floor 3", "BOT LEVEL=3.0", 3600),
    ("bot, floor 4 (hunter)", "BOT STUNTEST LEVEL=4.0", 5400),
    ("bot, floor 6 (boss)", "BOT LEVEL=6.0", 3600),
    ("guardians killed in one frame", "BOT GUARDKILL LEVEL=1.0", 300),
    ("pickup chord over combat drums", "BOT CHORDTEST LEVEL=1.0", 1260),
    ("plasma rifle shockwave with both buttons held", "BOT PLASMATEST LEVEL=1.0", 300),
    ("mouse wheel past an empty gun", "BOT WHEELTEST=3.0 LEVEL=1.0", 300),
    ("mouse wheel with three guns", "BOT WHEELTEST=2.0 LEVEL=1.0", 300),
    ("exit waits for the Hunter", "BOT EXITTEST LEVEL=4.0", 300),
    ("Hunter rests after a dash bash", "BOT LUNGETEST LEVEL=4.0", 660),
]
FIRST_HIT = (5.0, 45.0)
STAND_DEATH = 90.0
STUCK = 3.0
REGEN = 0.35


def run(name, defines, frames, glsl):
    out = ROOT / "build" / "scenarios" / re.sub(r"\W+", "-", name).strip("-")
    command = [str(HERE / "shot.sh"), str(out), str(frames), "0", "0", "0", defines] + ([glsl] if glsl else [])
    subprocess.run(command, env={**os.environ, "SIZE": "320x180"}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    rows = []
    try:
        for line in (out / "log.txt").read_text().splitlines():
            if line.startswith("frame "):
                words = line.split()
                rows.append({words[k]: float(words[k + 1]) for k in range(0, len(words) - 1, 2)})
    except OSError:
        pass
    return rows


def check(name, rows, frames):
    if len(rows) < frames // 60 - 1:
        return [f"the run stopped after {len(rows)} of {frames // 60} log lines (see build/scenarios/)"], "no result"
    failures, notes = [], []
    stuck = max(r.get("stuck", 0.0) for r in rows)
    notes.append(f"stuck monster-seconds {stuck:.1f} (limit {STUCK:.0f})")
    if stuck > STUCK:
        failures.append(f"awake monsters stood still away from the player for {stuck:.1f} s in total")
    regen = max([(b["health100"] - a["health100"]) / 100 for a, b in zip(rows, rows[1:])
                 if a["dead10"] == 0 and b["dead10"] == 0 and a["level"] == b["level"]] or [0.0])
    notes.append(f"max regen {regen:.2f}/s (limit {REGEN})")
    if regen > REGEN:
        failures.append(f"health rose {regen:.2f} in one second")
    if name.startswith("guardians"):
        drops = int(rows[-1]["weapon"])
        notes.append(f"upgrades {drops // 10}, crates {drops % 10} (needs 1 and 2)")
        if drops != 12:
            failures.append("three guardians killed together must drop one upgrade and two crates")
    if name.startswith("pickup chord"):
        voices = int(rows[-1]["weapon"])
        notes.append(f"fewest chord notes playing {voices} (needs 3)")
        if voices < 3:
            failures.append("a chord note was stolen by the music before it started")
    if name.startswith("plasma rifle"):
        left = rows[-1]["weapon"]
        notes.append(f"plasma ammo left {left:.0f} of 90 after 1.8 s of fire (needs 70, two shockwaves and no bolts)")
        if left != 70:
            failures.append("holding both buttons on the plasma rifle did not fire exactly two shockwaves")
    if name.startswith("mouse wheel"):
        seen, want = int(rows[-1]["weapon"]), 5 if "three" in name else 13
        notes.append(f"guns reached {[g for g in range(4) if seen >> g & 1]} (needs {[g for g in range(4) if want >> g & 1]})")
        if seen != want:
            failures.append("the wheel reached a gun it should not (empty or not owned) or missed a loaded one")
    if name.startswith("Hunter rests"):
        gap = rows[-1]["weapon"] / 10
        notes.append(f"shortest gap between lunges {gap:.1f} s (needs 2.0 to 99)")
        if not 2.0 <= gap < 99.0:
            failures.append("a dash bash cut the Hunter's rest short, or it lunged fewer than twice")
    if name.startswith("exit waits"):
        state = int(rows[-1]["weapon"])
        notes.append(f"exit open before the kill {state // 10}, after it {state % 10} (needs 0 and 1)")
        if state != 1:
            failures.append("with three fuses on floor 4 the exit opened while the Hunter lived, or stayed shut after it died")
    if "hunter" in name:
        fuses = max(int(r["left"]) // 100 for r in rows)
        notes.append(f"fuses {fuses} (needs 1)")
        if fuses < 1:
            failures.append("the bot found no fuse on the hunter floor in 90 s")
        bites = int(rows[-1]["weapon"])
        notes.append(f"bites by stunned monsters {bites} (needs 0)")
        if bites:
            failures.append("a stunned monster finished a lunge on the player")
    if name.startswith("standing"):
        hit = next((r["frame"] / 60 for r in rows if r["health100"] < 100), None)
        death = next((r["frame"] / 60 for r in rows if r["dead10"] > 0), None)
        notes.append(f"first hit {'never' if hit is None else f'{hit:.0f} s'} (limits {FIRST_HIT[0]:.0f}-{FIRST_HIT[1]:.0f}), "
                     f"death {'never' if death is None else f'{death:.0f} s'} (limit {STAND_DEATH:.0f})")
        if hit is None or not FIRST_HIT[0] <= hit <= FIRST_HIT[1]:
            failures.append("first hit outside the limits (monsters idle, or spawn-killing)")
        if death is None or death > STAND_DEATH:
            failures.append("a player who never moves was not killed")
    return failures, ", ".join(notes)


def main():
    args = sys.argv[1:]
    report = None
    if "--report" in args:
        at = args.index("--report")
        if at + 1 >= len(args):
            sys.exit(__doc__.strip().split("\n\n")[1])
        report = args[at + 1]
        del args[at:at + 2]
    glsl = args[0] if args else None
    inputs = [pathlib.Path(glsl) if glsl else ROOT / "src" / "game.glsl", HERE / "scenarios.py", HERE / "shot.c", HERE / "shot.sh",
              ROOT / "tools" / "minify_glsl.py"]
    try:
        digest = hashlib.sha1(b"".join(path.read_bytes() for path in inputs)).hexdigest()
    except OSError as error:
        sys.exit(f"{error.filename}: {error.strerror}")
    stamp = pathlib.Path(report + ".stamp") if report else None
    if stamp and stamp.is_file() and pathlib.Path(report).is_file() and stamp.read_text().strip() == digest:
        print(pathlib.Path(report).read_text(), end="")
        print("(saved result: the shader and the scenario tools are unchanged since it passed)")
        sys.exit(0)
    if stamp:
        stamp.unlink(missing_ok=True)
    jobs = os.environ.get("JOBS", "4")
    if not jobs.isdigit() or int(jobs) < 1:
        sys.exit("JOBS must be a positive integer")
    with concurrent.futures.ThreadPoolExecutor(int(jobs)) as pool:
        results = list(pool.map(lambda s: run(s[0], s[1], s[2], glsl), SCENARIOS))
    lines, failed = [], False
    for (name, defines, frames), rows in zip(SCENARIOS, results):
        failures, notes = check(name, rows, frames)
        lines.append(f"{'FAIL' if failures else 'ok  '} {name}: {notes}")
        lines.extend(f"     - {failure}" for failure in failures)
        failed = failed or bool(failures)
    text = "\n".join(lines)
    print(text)
    if report:
        pathlib.Path(report).write_text(text + "\n")
        if not failed:
            stamp.write_text(digest + "\n")
    sys.exit(1 if failed else 0)


main()
