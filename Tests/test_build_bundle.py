"""Check shell bundle assembly without Xcode; iconutil is a test double."""

import argparse
import os
from pathlib import Path
import plistlib
import shutil
import statistics
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]


def assemble(script, project, build):
    subprocess.run(
        [
            "bash", "-euc",
            '''
source "$1"
iconutil() { test "$1" = -c && test "$2" = icns && test -d "$3"; }
assemble_app_bundle "$3/UniFiBar.app" "$3/UniFiBar" "$2" "$3"
''',
            "bundle-test", str(script), str(project), str(build),
        ],
        env={**os.environ, "APP_NAME": "UniFiBar", "APP_VERSION": "1.2.3", "BUILD_NUMBER": "4"},
        check=True,
        stdout=subprocess.DEVNULL,
    )


def check_bundle(project, build):
    bundle = build / "UniFiBar.app/Contents"
    with (bundle / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    assert info["CFBundleExecutable"] == "UniFiBar"
    assert info["CFBundleShortVersionString"] == "1.2.3"
    assert info["CFBundleVersion"] == "4"
    assert info["LSMinimumSystemVersion"] == "26.0"
    assert info["LSUIElement"] is True
    assert (bundle / "MacOS/UniFiBar").read_bytes() == (build / "UniFiBar").read_bytes()
    assert os.access(bundle / "MacOS/UniFiBar", os.X_OK)
    assert (bundle / "Resources/UniFiBar.entitlements").read_bytes() == (project / "UniFiBar.entitlements").read_bytes()
    assets = project / "Resources/Assets.xcassets"
    icons = list((assets / "AppIcon.appiconset").glob("icon_*.png"))
    assert len(icons) == 10
    assert {p.name for p in (build / "AppIcon.iconset").iterdir()} == {p.name for p in icons}
    for icon in icons:
        assert (build / "AppIcon.iconset" / icon.name).read_bytes() == icon.read_bytes()
    for icon in (assets / "StatusBarIcon.imageset").glob("*.png"):
        assert (bundle / "Resources" / icon.name).read_bytes() == icon.read_bytes()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--script", type=Path, default=ROOT / "Scripts/build_common.sh")
    parser.add_argument("--benchmark", action="store_true", help="Measure shell staging, not icon conversion or app runtime.")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="unifibar-bundle-") as temporary:
        project = Path(temporary) / "project with spaces"
        shutil.copytree(ROOT / "Resources", project / "Resources")
        shutil.copy(ROOT / "UniFiBar.entitlements", project)
        build = project / ".build"
        build.mkdir()
        shutil.copy2("/bin/true", build / "UniFiBar")
        assemble(args.script.resolve(), project, build)
        check_bundle(project, build)
        stale = build / "UniFiBar.app/stale"
        stale.touch()
        assemble(args.script.resolve(), project, build)
        check_bundle(project, build)
        assert not stale.exists()
        if args.benchmark:
            samples = []
            for _ in range(7):
                start = time.perf_counter()
                for _ in range(20):
                    assemble(args.script.resolve(), project, build)
                samples.append((time.perf_counter() - start) * 1000 / 20)
            check_bundle(project, build)
            print("Shell staging with test-double iconutil: 7 rounds x 20 bundles")
            print("Round means (ms):", ", ".join(f"{sample:.2f}" for sample in samples))
            print(f"Median: {statistics.median(samples):.2f} ms/bundle")
        missing_icon = project / "Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16.png"
        missing_icon.unlink()
        assemble(args.script.resolve(), project, build)
        assert not (build / "AppIcon.iconset/icon_16x16.png").exists()
        assert len(list((build / "AppIcon.iconset").glob("*.png"))) == 9
        shutil.rmtree(project / "Resources")
        assemble(args.script.resolve(), project, build)
        assert not (build / "UniFiBar.app/Contents/Resources/icon@2x.png").exists()
    print("PASS: bundle metadata, binary, icons, rebuild, spaces, and missing optional assets")


if __name__ == "__main__":
    main()
