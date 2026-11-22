"""Builds and signs the over-the-air filter bundle (filters.json + .sig).

Run by .github/workflows/filters.yml. Reads the filter files from
Sift/Resources and the schema number from Sift/FilterUpdates.swift, so the
app and the bundle can never disagree about either.

    python scripts/build_filters.py OUT_DIR

Needs SIFT_FILTER_SIGNING_KEY (Ed25519 private key, PEM) in the environment.
"""

import base64
import json
import os
import pathlib
import re
import subprocess
import sys

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

ROOT = pathlib.Path(__file__).resolve().parent.parent
SWIFT = ROOT / "Sift" / "FilterUpdates.swift"
RESOURCES = ROOT / "Sift" / "Resources"


def swift_value(pattern):
    match = re.search(pattern, SWIFT.read_text(encoding="utf-8"), re.S)
    if not match:
        sys.exit(f"Could not find {pattern!r} in {SWIFT}")
    return match.group(1)


def main():
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "dist")
    out.mkdir(parents=True, exist_ok=True)

    schema = int(swift_value(r"static let schema = (\d+)"))
    names = re.findall(r'"([^"]+)"', swift_value(r"static let fileNames = \[(.*?)\]"))
    files = {}
    for name in names:
        path = RESOURCES / name
        if not path.is_file():
            sys.exit(f"Missing filter file {path}")
        files[name] = path.read_text(encoding="utf-8")

    commit = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, text=True).strip()
    version = int(subprocess.check_output(["git", "log", "-1", "--format=%ct"], cwd=ROOT, text=True).strip())

    data = json.dumps(
        {"schema": schema, "version": version, "commit": commit, "files": files},
        sort_keys=True, ensure_ascii=False, separators=(",", ":"),
    ).encode("utf-8")

    pem = os.environ.get("SIFT_FILTER_SIGNING_KEY", "").replace("\\n", "\n").encode()
    if not pem.strip():
        sys.exit("Missing SIFT_FILTER_SIGNING_KEY.")
    key = serialization.load_pem_private_key(pem, password=None)
    if not isinstance(key, Ed25519PrivateKey):
        sys.exit("SIFT_FILTER_SIGNING_KEY must be an Ed25519 private key.")

    # The app only accepts bundles signed by the key it was built with.
    embedded = swift_value(r'static let publicKeyBase64 = "([^"]+)"')
    public = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    if base64.b64encode(public).decode() != embedded:
        sys.exit("SIFT_FILTER_SIGNING_KEY does not match publicKeyBase64 in FilterUpdates.swift.")

    signature = base64.b64encode(key.sign(data)).decode()
    (out / "filters.json").write_bytes(data)
    (out / "filters.json.sig").write_text(signature + "\n", encoding="utf-8")
    print(f"Built filters.json: schema {schema}, version {version}, commit {commit}, {len(files)} files, {len(data)} bytes.")


if __name__ == "__main__":
    main()
