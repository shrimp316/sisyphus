"""Validate the v1.2 mastery inputs without changing any existing PNG.

Usage: python -X utf8 tests/mastery/audit_assets.py --zip <source.zip> --install-data
Pillow is used only to inspect image dimensions/alpha; no image is saved.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
from collections import Counter
from pathlib import Path, PurePosixPath
from zipfile import ZipFile

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PREFIX = "assets/ui/mastery/"
TRACKS = ("strength", "endurance", "breath")
EXPECTED = {"strength": "ΒΙΑΚΑΙΩΣΙΣ", "endurance": "ΜΕΓΑΛΗΡΩΜΗ", "breath": "ΤΑΧΕΙΑΠΝΟΗ"}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def rows(data: bytes) -> list[dict]:
    return list(csv.DictReader(io.StringIO(data.decode("utf-8-sig"), newline="")))


def write_csv(path: Path, data: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(data[0]))
        writer.writeheader()
        writer.writerows(data)


def copy_identical_or_new(path: Path, data: bytes) -> None:
    if path.exists():
        if path.read_bytes() != data:
            raise ValueError(f"Refusing to overwrite different existing file: {path}")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


def audit(archive: Path, install: bool) -> dict:
    checks: list[dict] = []

    def check(name: str, condition: bool, detail=None) -> None:
        checks.append({"name": name, "pass": bool(condition), "detail": detail})

    with ZipFile(archive) as source:
        files = [name for name in source.namelist() if not name.endswith("/")]
        check("unique_archive_paths", len(files) == len(set(files)))
        check("safe_archive_paths", all(not PurePosixPath(name).is_absolute() and ".." not in PurePosixPath(name).parts for name in files))
        source_root = files[0].split("/", 1)[0] + "/"
        runtime = {name[len(source_root):]: source.read(name) for name in files if name.startswith(source_root + PREFIX) and name.endswith(".png")}
        check("runtime_png_count_131", len(runtime) == 131, len(runtime))
        check("old_art_65", sum("/inscriptions/" not in name for name in runtime) == 65)
        check("greek_additions_66", sum("/inscriptions/" in name for name in runtime) == 66)

        def read(name: str) -> bytes:
            return source.read(source_root + name)

        mapping = rows(read("mastery_greek_node_mapping_v11.csv"))
        inventory = rows(read("mastery_asset_inventory_v1.csv"))
        artboard = rows(read("ARTBOARD_TO_ACTUAL_ASSETS.csv"))
        bank = json.loads(read("mastery_greek_inscription_bank_v11.json"))
        check("mapping_count_35", len(mapping) == 35)
        check("mapping_unique_ids", len(set(row["node_id"] for row in mapping)) == 35)
        check("mapping_tracks", Counter(row["track"] for row in mapping) == Counter(strength=10, endurance=10, breath=10, special=5))
        check("inventory_original_65", len(inventory) == 65)
        check("inventory_paths_equal_originals", set(row["relative_path"] for row in inventory) == {name for name in runtime if "/inscriptions/" not in name})
        for row in inventory:
            blob = runtime.get(row["relative_path"], b"")
            check("original_inventory_sha:" + row["asset_id"], sha(blob) == row["sha256"])

        image_rows = []
        missing = []
        conflicts = []
        for name, blob in sorted(runtime.items()):
            target = ROOT / name
            match = target.exists() and target.read_bytes() == blob
            if not target.exists():
                missing.append(name)
            elif not match:
                conflicts.append(name)
            with Image.open(io.BytesIO(blob)) as image:
                image.load()
                alpha = image.getchannel("A") if "A" in image.getbands() else None
                bounds = alpha.getbbox() if alpha is not None else (0, 0, image.width, image.height)
                extrema = alpha.getextrema() if alpha is not None else (255, 255)
                image_rows.append({"relative_path": name, "group": "greek" if "/inscriptions/" in name else "original", "width": image.width, "height": image.height, "mode": image.mode, "bytes": len(blob), "alpha_bbox": json.dumps(bounds), "alpha_min": extrema[0], "alpha_max": extrema[1], "sha256": sha(blob), "existing_byte_match": match})
                for inv in inventory:
                    if inv["relative_path"] == name:
                        check("inventory_dimensions:" + inv["asset_id"], (image.width, image.height) == (int(inv["width"]), int(inv["height"])))
                        check("inventory_bytes:" + inv["asset_id"], len(blob) == int(inv["size_bytes"]))
        check("no_existing_png_conflicts", not conflicts, conflicts)

        for row in mapping:
            track = row["track"]
            index = int(row["index"])
            special = track == "special"
            expected_xy = (555 + 147 * (index - 1), 856) if special else (425 + 96 * (index - 1), {"strength": 434, "endurance": 572, "breath": 708}[track])
            check("coordinates:" + row["node_id"], (int(row["x"]), int(row["y"])) == expected_xy)
            check("id:" + row["node_id"], row["node_id"] == f"act1_{track}_{index:02d}" and row["act"] == "1")
            for key in ("base_asset", "icon_asset", "frame_asset", "status_layer"):
                if row[key]:
                    check(f"mapping_path:{row['node_id']}:{key}", PREFIX + row[key] in runtime, row[key])
            if special:
                check("special_unassigned:" + row["node_id"], all(not row[key] for key in ("greek_letter", "greek_codepoint", "rune_face_png", "glyph_engraved_png", "glyph_ready_png", "glyph_active_png")) and row["is_placeholder"].lower() == "true")
                check("special_placeholder:" + row["node_id"], row["icon_asset"] == f"special/special_placeholder_{index:02d}.png")
            else:
                letter = EXPECTED[track][index - 1]
                codepoint = f"{ord(letter):04X}"
                check("letter:" + row["node_id"], row["greek_letter"] == letter and row["greek_codepoint"] == codepoint)
                check("rune_face:" + row["node_id"], row["rune_face_png"] in runtime)
                for state in ("engraved", "ready", "active"):
                    path = f"{PREFIX}inscriptions/glyphs/{state}/{codepoint}.png"
                    check(f"glyph:{row['node_id']}:{state}", row[f"glyph_{state}_png"] == path and path in runtime)
        milestone_counts = {}
        for distance, expected_counts in [(0, (0, 0, 0)), (250, (4, 3, 3)), (500, (7, 7, 6)), (750, (10, 10, 10))]:
            counts = [sum(row["track"] == track and int(row["milestone_m"]) <= distance for row in mapping if row["track"] != "special") for track in TRACKS]
            milestone_counts[str(distance)] = dict(zip(TRACKS, counts))
            check(f"milestone:{distance}", tuple(counts) == expected_counts)
        inscriptions = []
        check("inscription_acts_4", set(bank["inscriptions"]) == {"1", "2", "3", "4"})
        for act, tracks in bank["inscriptions"].items():
            check("inscription_tracks:" + act, set(tracks) == set(TRACKS))
            for track, entry in tracks.items():
                core = entry["coreText"]
                check(f"core_length:{act}:{track}", len(core) == 10, core)
                if act == "1":
                    check("act1_core:" + track, core == EXPECTED[track])
                for letter in core:
                    for state in ("engraved", "ready", "active"):
                        check(f"bank_glyph:{act}:{track}:{ord(letter):04X}:{state}", f"{PREFIX}inscriptions/glyphs/{state}/{ord(letter):04X}.png" in runtime)
                inscriptions.append({"act": int(act), "track": track, "coreText": core, "codepoint_length": len(core), "legacy_extension_unassigned": entry["extensionText_legacy_unassigned"]})
        for entry in artboard:
            for component in entry["actual_file_or_composition"].split(" + "):
                check("artboard_actual_target:" + component, PREFIX + component in runtime)
        check("glyph_files_21_each_state", all(sum(f"/glyphs/{state}/" in name for name in runtime) == 21 for state in ("engraved", "ready", "active")))

        # All checks and collisions are evaluated before any optional copy.
        passed = all(item["pass"] for item in checks)
        if install and not passed:
            raise ValueError("Audit failed; refusing to install data/assets: " + repr([item for item in checks if not item["pass"]]))
        if install:
            for name, blob in runtime.items():
                copy_identical_or_new(ROOT / name, blob)
            copies = {"mastery_greek_node_mapping_v11.csv": "data/mastery/mastery_node_layout_v12.csv", "mastery_greek_inscription_bank_v11.json": "data/mastery/mastery_greek_inscriptions_v12.json", "mastery_node_layout_v1.csv": "docs/mastery/source/mastery_node_layout_v1.csv", "mastery_asset_inventory_v1.csv": "docs/mastery/source/mastery_asset_inventory_v1.csv", "ARTBOARD_TO_ACTUAL_ASSETS.csv": "docs/mastery/source/ARTBOARD_TO_ACTUAL_ASSETS.csv", "README_GREEK_RESTORATION.md": "docs/mastery/source/README_GREEK_RESTORATION.md", "README_KR.md": "docs/mastery/source/README_KR.md"}
            for original, destination in copies.items():
                copy_identical_or_new(ROOT / destination, read(original))

        check("runtime_files_byte_match_after", all((ROOT / name).exists() and (ROOT / name).read_bytes() == blob for name, blob in runtime.items()))
        source_copies = {"data/mastery/mastery_node_layout_v12.csv": "mastery_greek_node_mapping_v11.csv", "data/mastery/mastery_greek_inscriptions_v12.json": "mastery_greek_inscription_bank_v11.json"}
        for path, original in source_copies.items():
            check("data_source_byte_match:" + path, (ROOT / path).exists() and (ROOT / path).read_bytes() == read(original))
        write_csv(ROOT / "docs/mastery/asset_sha256_v12.csv", image_rows)
        write_csv(ROOT / "data/mastery/mastery_asset_mapping_v12.csv", [{"resource_path": "res://" + item["relative_path"], **item} for item in image_rows])
        tree_path = ROOT / "docs/mastery/source/archive_tree.txt"
        tree_path.parent.mkdir(parents=True, exist_ok=True)
        tree_path.write_text("\n".join(files) + "\n", encoding="utf-8")
        result = {"pass": all(item["pass"] for item in checks), "check_count": len(checks), "failed": [item for item in checks if not item["pass"]], "archive_name": archive.name, "archive_sha256": sha(archive.read_bytes()), "runtime_png_count": len(runtime), "original_png_count": 65, "greek_png_count": 66, "runtime_png_bytes": sum(len(blob) for blob in runtime.values()), "existing_byte_matches_before": len(runtime) - len(missing) - len(conflicts), "missing_before": missing, "conflicts_before": conflicts, "mapping_count": len(mapping), "milestone_counts": milestone_counts, "inscriptions": inscriptions, "artboard_mapping_methods": dict(Counter(row["matching_method"] for row in artboard)), "not_runtime_files": [name for name in files if name[len(source_root):] not in runtime], "checks": checks}
        output = ROOT / "tests/mastery/results/v12/asset_audit.json"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", required=True, type=Path)
    parser.add_argument("--install-data", action="store_true")
    args = parser.parse_args()
    report = audit(args.zip, args.install_data)
    print(json.dumps({key: report[key] for key in ("pass", "check_count", "failed", "runtime_png_count", "existing_byte_matches_before", "missing_before", "conflicts_before")}, ensure_ascii=False))
    raise SystemExit(0 if report["pass"] else 1)
