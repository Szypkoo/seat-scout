#!/usr/bin/env python3
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
APP = ROOT / "app"
ANDROID = APP / "Android"
OUTPUT = ROOT / "dist" / "SeatScout.apk"


def build_core():
    script = ROOT / "core" / "build_android.sh"
    if script.exists():
        print("==> Budowanie silnika core dla Androida...")
        subprocess.run([str(script)], check=True)


def find_gradle():
    gradlew = ANDROID / "gradlew"
    if gradlew.exists() and os.access(gradlew, os.X_OK):
        return [str(gradlew)]
    gradle = shutil.which("gradle")
    if gradle:
        return [gradle]
    return None


def build(build_type="release"):
    build_core()

    # If skip CLI is installed, skip export can be used
    skip = shutil.which("skip")
    if skip:
        print("==> Budowanie paczki Android za pomocą Skip...")
        cmd = [skip, "export", "--type", "apk"]
        if build_type == "release":
            cmd.append("--release")
        subprocess.run(cmd, cwd=APP, check=True)
        # Search for generated APK
        apk_candidates = list((APP / ".build").glob("**/*.apk"))
        if apk_candidates:
            return apk_candidates[0]

    # Alternatively, use Gradle directly in app/Android
    gradle_cmd = find_gradle()
    if gradle_cmd:
        task = "assembleRelease" if build_type == "release" else "assembleDebug"
        print(f"==> Budowanie APK za pomocą Gradle ({task})...")
        subprocess.run(gradle_cmd + [task], cwd=ANDROID, check=True)
        apk_dir = ANDROID / "app" / "build" / "outputs" / "apk" / build_type
        apk_candidates = list(apk_dir.glob("*.apk"))
        if apk_candidates:
            return apk_candidates[0]

    raise RuntimeError(
        "Nie znaleziono narzędzia 'skip' ani 'gradle'/'gradlew' w PATH.\n"
        "Aby zbudować aplikację na Androida:\n"
        "  1. Uruchom projekt w Xcode na macOS (zainstalowany Skip zajmie się wszystkim automatycznie),\n"
        "  2. Albo zainstaluj Gradle / Android SDK na maszynie deweloperskiej."
    )


def package(source: Path):
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, OUTPUT)
    print(f"\n[SUKCES] Paczka Android gotowa: {OUTPUT}")


def main():
    parser = argparse.ArgumentParser(description="Buduje paczkę Seat Scout dla Androida (.apk)")
    parser.add_argument("--package-only", type=Path, metavar="APK", help="użyj gotowego pliku APK")
    parser.add_argument("--debug", action="store_true", help="zbuduj wariant debug zamiast release")
    args = parser.parse_args()

    try:
        if args.package_only:
            package(args.package_only)
        else:
            build_type = "debug" if args.debug else "release"
            apk = build(build_type)
            package(apk)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Błąd: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
