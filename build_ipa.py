#!/usr/bin/env python3
import argparse
import plistlib
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
APP = ROOT / "app"
OUTPUT = ROOT / "dist" / "SeatScout.ipa"


def build():
    xtool = shutil.which("xtool")
    if xtool is None:
        raise RuntimeError("Nie znaleziono xtool w PATH")
    subprocess.run([str(ROOT / "core" / "build_ios.sh")], check=True)
    subprocess.run([xtool, "dev", "build", "-c", "release", "--ipa"], cwd=APP, check=True)
    return APP / "xtool" / "SeatScout.ipa"


def package(source):
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(source) as original:
        names = original.namelist()
        plists = [name for name in names if name.startswith("Payload/") and name.endswith(".app/Info.plist") and name.count("/") == 2]
        if len(plists) != 1:
            raise RuntimeError("Nie znaleziono Info.plist aplikacji w paczce")
        with zipfile.ZipFile(OUTPUT, "w") as output:
            for item in original.infolist():
                data = original.read(item)
                if item.filename == plists[0]:
                    info = plistlib.loads(data)
                    bundle_id = info.get("CFBundleIdentifier")
                    if not bundle_id:
                        raise RuntimeError("Brak identyfikatora aplikacji w Info.plist")
                    info["BGTaskSchedulerPermittedIdentifiers"] = [f"{bundle_id}.refresh"]
                    modes = info.get("UIBackgroundModes", [])
                    if "fetch" not in modes:
                        modes.append("fetch")
                    info["UIBackgroundModes"] = modes
                    info["NSSupportsLiveActivities"] = True
                    data = plistlib.dumps(info)
                output.writestr(item, data)
    print(f"Paczka: {OUTPUT}")
    print("Przed instalacją podpisz ponownie aplikację i widżet.")


def main():
    parser = argparse.ArgumentParser(description="Buduje paczkę Seat Scout dla iOS")
    parser.add_argument("--package-only", type=Path, metavar="IPA", help="przygotuj istniejącą paczkę xtool")
    args = parser.parse_args()
    try:
        package(args.package_only if args.package_only else build())
    except (OSError, RuntimeError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"Błąd: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
