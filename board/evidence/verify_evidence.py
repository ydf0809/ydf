"""Verify the board evidence archive against its manifest."""

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
REPOSITORY = ROOT.parents[1]
MANIFEST = ROOT / "report/evidence_index.json"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    errors = []
    source = REPOSITORY / data["source_document"]
    if not source.is_file():
        errors.append({"kind": "source_missing", "path": data["source_document"]})
    elif sha256(source) != data["source_sha256"]:
        errors.append({"kind": "source_changed", "path": data["source_document"]})

    for record in data["records"]:
        path = ROOT / record["file"]
        if not path.is_file():
            errors.append({"kind": "evidence_missing", "path": record["file"]})
        elif path.stat().st_size != record["bytes"] or sha256(path) != record["sha256"]:
            errors.append({"kind": "evidence_changed", "path": record["file"]})

    result = {
        "status": "PASS" if not errors else "FAIL",
        "source_document": data["source_document"],
        "records_checked": data["record_count"],
        "errors": errors,
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
