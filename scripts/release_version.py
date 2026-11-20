"""Choose the next patch version from fetched remote tags; never rewrite a release."""
import os
import re
import subprocess
from pathlib import Path


def next_version(tags):
    versions = []
    for tag in tags:
        match = re.fullmatch(r"v(\d+)\.(\d+)(?:\.(\d+))?", tag)
        if match:
            versions.append(tuple(int(value or 0) for value in match.groups()))
    major, minor, patch = max(versions, default=(1, 0, -1))
    return f"{major}.{minor}.{patch + 1}"


if __name__ == "__main__":
    if os.environ.get("GITHUB_REF_TYPE") == "tag":
        tag = os.environ["GITHUB_REF_NAME"]
        if not re.fullmatch(r"v\d+\.\d+(?:\.\d+)?", tag):
            raise SystemExit("Invalid version tag")
        print(tag[1:])
    elif os.environ.get("GITHUB_REF_NAME", "master") == "master":
        tags = subprocess.check_output(["git", "tag", "--list", "v*"], text=True).splitlines()
        print(next_version(tags))
    else:
        print((Path(__file__).resolve().parents[1] / "VERSION").read_text().strip())
