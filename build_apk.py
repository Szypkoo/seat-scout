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


def setup_env():
    env = os.environ.copy()
    home = Path.home()

    # Discover JDK 21 or installed JDK
    jdk_dir = home / ".local" / "share" / "jvm" / "jdk-21.0.13+9"
    if "JAVA_HOME" not in env and jdk_dir.exists():
        env["JAVA_HOME"] = str(jdk_dir)
        env["PATH"] = f"{jdk_dir}/bin:{env.get('PATH', '')}"

    # Discover Android SDK
    android_sdk = home / "Android" / "Sdk"
    if "ANDROID_HOME" not in env and android_sdk.exists():
        env["ANDROID_HOME"] = str(android_sdk)
        env["PATH"] = f"{android_sdk}/platform-tools:{android_sdk}/cmdline-tools/latest/bin:{env.get('PATH', '')}"

    # Discover Android NDK
    ndk_dir = android_sdk / "ndk" / "27.2.12479018"
    if "ANDROID_NDK_HOME" not in env and ndk_dir.exists():
        env["ANDROID_NDK_HOME"] = str(ndk_dir)

    # Local lib for ncurses compatibility
    local_lib = home / ".local" / "lib"
    if local_lib.exists():
        current_ld = env.get("LD_LIBRARY_PATH", "")
        env["LD_LIBRARY_PATH"] = f"{local_lib}:{current_ld}" if current_ld else str(local_lib)

    return env


def build_core(env):
    script = ROOT / "core" / "build_android.sh"
    if script.exists():
        print("==> Budowanie silnika core dla Androida...")
        subprocess.run([str(script)], cwd=ROOT / "core", env=env, check=True)


def find_gradle():
    gradlew = ANDROID / "gradlew"
    if gradlew.exists() and os.access(gradlew, os.X_OK):
        return [str(gradlew)]
    gradle = shutil.which("gradle")
    if gradle:
        return [gradle]
    return None


def build(build_type="release"):
    env = setup_env()
    build_core(env)

    # If skip CLI is installed, skip export can be used
    skip = shutil.which("skip")
    if skip:
        print("==> Budowanie paczki Android za pomocą Skip...")
        cmd = [skip, "export", "--type", "apk"]
        if build_type == "release":
            cmd.append("--release")
        try:
            subprocess.run(cmd, cwd=APP, env=env, check=True)
            apk_candidates = list((APP / ".build").glob("**/*.apk"))
            if apk_candidates:
                return apk_candidates[0]
        except subprocess.CalledProcessError:
            print("==> Skip export wymaga dodatkowej konfiguracji, przełączam na Gradle...")

    # Alternatively, use Gradle directly in app/Android
    gradle_cmd = find_gradle()
    if gradle_cmd:
        task = "assembleRelease" if build_type == "release" else "assembleDebug"
        print(f"==> Budowanie APK za pomocą Gradle ({task})...")
        subprocess.run(gradle_cmd + [task], cwd=ANDROID, env=env, check=True)
        apk_dir = ANDROID / "app" / "build" / "outputs" / "apk" / ("release" if build_type == "release" else "debug")
        apk_candidates = list(apk_dir.glob("*.apk"))
        if apk_candidates:
            return apk_candidates[0]

    raise RuntimeError(
        "Nie udało się znaleźć zbudowanego pliku APK.\n"
        "Upewnij się, że Gradle zakończył budowanie bez błędów."
    )


def package(source: Path, share: bool = False):
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, OUTPUT)
    print(f"\n[SUKCES] Paczka Android gotowa: {OUTPUT}")
    if share:
        omarchy = shutil.which("omarchy")
        if omarchy:
            print(f"==> Udostępnianie przez omarchy share (LocalSend)...")
            subprocess.run([omarchy, "share", "file", str(OUTPUT)])


def main():
    parser = argparse.ArgumentParser(description="Buduje paczkę Seat Scout dla Androida (.apk)")
    parser.add_argument("--package-only", type=Path, metavar="APK", help="użyj gotowego pliku APK")
    parser.add_argument("--debug", action="store_true", help="zbuduj wariant debug zamiast release")
    parser.add_argument("--share", action="store_true", help="udostępnij gotowy plik APK przez omarchy share (LocalSend)")
    args = parser.parse_args()

    try:
        if args.package_only:
            package(args.package_only, share=args.share)
        else:
            build_type = "debug" if args.debug else "release"
            apk = build(build_type)
            package(apk, share=args.share)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Błąd: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
