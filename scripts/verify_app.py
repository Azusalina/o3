"""Fail the release if the archive omits its executable, Core ML model, or Files settings."""
from pathlib import Path
import plistlib
import sys

app = Path(sys.argv[1])
info = plistlib.loads((app / "Info.plist").read_bytes())
assert (app / info["CFBundleExecutable"]).is_file(), "Executable missing"
assert info["CFBundleShortVersionString"] == "1.0", "Wrong release version"
assert float(info["MinimumOSVersion"]) == 18.0, "Wrong iOS minimum"
assert info["UIFileSharingEnabled"] and info["LSSupportsOpeningDocumentsInPlace"], "Files access disabled"
models = list(app.rglob("RawForgeSuperLight.mlmodelc"))
assert len(models) == 1 and any(models[0].iterdir()), "Compiled RawForge model missing"
assert (app / "RawForge-LICENSE.txt").is_file(), "Model license missing"
assert not (app / "embedded.mobileprovision").exists(), "Expected unsigned distribution"
print(f"Verified {app.name}: version 1.0, iOS 18+, executable, compiled Core ML model, Files access, license")
