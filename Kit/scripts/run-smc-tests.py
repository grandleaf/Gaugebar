#!/usr/bin/env python3
"""Run: python3 Kit/scripts/run-smc-tests.py (macOS, Xcode, Python 3).

Runs Tests/SMC.swift with fake IOKit calls. Gaugebar only reads the SMC, so this
also fails if code that writes to it comes back.
Production source is unchanged; temporary build files are removed.
This standalone suite is independent of the existing Xcode Tests target.
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "Tests"
BOUNDARIES = (
    "IOServiceMatching", "IOServiceGetMatchingServices", "IOIteratorNext",
    "IOObjectRelease", "IOServiceOpen", "IOServiceClose",
    "IOConnectCallStructMethod",
)


def run():
    platform = Path(subprocess.check_output(
        ["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"], text=True).strip())
    frameworks = platform / "Developer/Library/Frameworks"
    private_frameworks = platform / "Developer/Library/PrivateFrameworks"
    libraries = platform / "Developer/usr/lib"
    if not (frameworks / "XCTest.framework").exists():
        raise RuntimeError("XCTest requires a full Xcode installation selected with xcode-select")
    source = (ROOT / "SMC/smc.swift").read_text()
    if re.search(r"writeBytes|func write\b|setFan|= 6\b", source):
        raise RuntimeError("SMC/smc.swift must stay read-only")
    # Keep production algorithms and connection lifecycle intact. Only redirect
    # OS calls in a disposable copy; never compile the live driver into tests.
    for name in BOUNDARIES:
        source, count = re.subn(r"\b" + name + r"(?=\()", "mock" + name, source)
        if not count:
            raise RuntimeError(f"Missing expected OS boundary: {name}")
    if re.search(r"\b(?:" + "|".join(BOUNDARIES) + r")\s*\(", source):
        raise RuntimeError("An unmocked OS call remains")
    tests = (TESTS / "SMC.swift").read_text()
    names = re.findall(r"^    func (test\w+)\(\)", tests, re.MULTILINE)
    if not names or len(names) != len(set(names)):
        raise RuntimeError("Missing or duplicate tests")
    with tempfile.TemporaryDirectory(prefix="gaugebar-smc-tests-") as directory:
        build = Path(directory)
        (build / "SMCUnderTest.swift").write_text(source)
        env = dict(os.environ, SWIFT_MODULECACHE_PATH=str(build / "cache"))
        (build / "main.swift").write_text(
            "import XCTest\nimport Darwin\n"
            "let suite = SMCTests.defaultTestSuite\nsuite.run()\n"
            f"exit(suite.testRun?.hasSucceeded == true && suite.testRun?.executionCount == {len(names)} ? 0 : 1)\n"
        )
        print(f"\nRunning {len(names)} SMC tests", flush=True)
        executable = build / "smc-tests"
        subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-g",
                        "-module-cache-path", str(build / "cache"),
                        "-I", str(libraries), "-L", str(libraries),
                        "-Xlinker", "-rpath", "-Xlinker", str(libraries),
                        "-F", str(frameworks), "-Xlinker", "-rpath", "-Xlinker", str(frameworks),
                        "-Xlinker", "-rpath", "-Xlinker", str(private_frameworks),
                        str(build / "SMCUnderTest.swift"),
                        str(TESTS / "SMC.swift"), str(build / "main.swift"),
                        "-o", str(executable)], check=True, env=env, timeout=180)
        subprocess.run([str(executable)], check=True, env=env, timeout=60)


if __name__ == "__main__":
    run()
