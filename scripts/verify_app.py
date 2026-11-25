"""Fail the release if the archive omits its executable, Core ML model, or Files settings."""
from pathlib import Path
import plistlib
import sys

app = Path(sys.argv[1])
info = plistlib.loads((app / "Info.plist").read_bytes())
assert (app / info["CFBundleExecutable"]).is_file(), "Executable missing"
expected = sys.argv[2]
assert info["CFBundleShortVersionString"] == expected, "Wrong release version"
assert float(info["MinimumOSVersion"]) == 18.0, "Wrong iOS minimum"
assert info["UIFileSharingEnabled"] and info["LSSupportsOpeningDocumentsInPlace"], "Files access disabled"
import json
catalog = json.loads((Path(__file__).resolve().parent / "model_catalog.json").read_text())
for entry in catalog.values():
    models = list(app.rglob(entry["bundle"] + ".mlmodelc"))
    assert len(models) == 1 and any(models[0].iterdir()), f"Compiled model missing: {entry['bundle']}"
assert (app / "RawForge-LICENSE.txt").is_file(), "Model license missing"
assert not (app / "embedded.mobileprovision").exists(), "Expected unsigned distribution"
print(f"Verified {app.name}: version {expected}, iOS 18+, executable, compiled Core ML model, Files access, license")
