#!/usr/bin/env python3
"""Run disjoint seed shards in hidden Godot processes and merge only a complete dataset."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


def code_hashes(project, script="tests/balance/simulator.gd"):
    files = list((project / "scripts").glob("*.gd"))
    files += [project / "tests/balance/simulator.gd", project / "tests/balance/balance_controller.gd"]
    files += [project / "tests/balance/policies.json", project / "project.godot"]
    files += list((project / "data").rglob("*.tres"))
    # Follow literal resource dependencies of alternate experiment harnesses.
    # Keep separate probe/verifier files outside the running simulation's hash set.
    pending, visited = [project / script], set()
    while pending:
        path = pending.pop().resolve()
        if path in visited:
            continue
        path.relative_to(project)
        visited.add(path)
        if path.suffix == ".gd":
            for resource in re.findall(r'res://([^"\s]+\.(?:gd|json|tres))', path.read_text(encoding="utf-8")):
                # Generated evidence is an output, not a startup dependency.
                # Its producing source and recorded generated hash remain audited.
                if "%" not in resource and not resource.replace("\\", "/").startswith("tests/balance/results/"):
                    pending.append(project / resource)
    files += list(visited)
    return {str(path.relative_to(project)).replace("\\", "/"): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(set(files))}


def run_shard(engine, project, dataset, index, config, timeout, script="tests/balance/simulator.gd"):
    config_path = dataset / f"worker_{index:02d}.json"
    data_path = dataset / f"worker_{index:02d}.jsonl"
    log_path = dataset / f"worker_{index:02d}.log"
    config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    command = [str(engine), "--headless", "--path", str(project), "--script", script, "--", "--config", str(config_path), "--output", str(data_path)]
    start = time.monotonic()
    with log_path.open("w", encoding="utf-8") as log:
        process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, cwd=project,
                                 creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                                 timeout=timeout, check=False)
    if process.returncode:
        raise RuntimeError(f"Worker {index} failed ({process.returncode}): {log_path}")
    log_text = log_path.read_text(encoding="utf-8", errors="replace")
    if "SCRIPT ERROR:" in log_text or "ERROR:" in log_text:
        raise RuntimeError(f"Worker {index} reported engine errors: {log_path}")
    records = [json.loads(line) for line in data_path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
    expected = sum(len(job["seeds"]) for job in config["jobs"])
    terminal = [row for row in records if row.get("type") == "campaign" or (row.get("type") == "run" and not row.get("campaign_id"))]
    if len(terminal) != expected:
        raise RuntimeError(f"Worker {index} produced {len(terminal)}/{expected} terminal samples; incomplete dataset")
    return {"worker": index, "seed_samples": expected, "actual_runs": sum(row.get("type") == "run" for row in records),
            "wall_seconds": time.monotonic() - start, "output": data_path.name, "command": command}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path, help="New directory; existing datasets are never overwritten")
    parser.add_argument("--project", default=Path(__file__).resolve().parents[2], type=Path)
    parser.add_argument("--workers", default=3, type=int)
    parser.add_argument("--worker-timeout", default=14400, type=int)
    parser.add_argument("--script", default="tests/balance/simulator.gd", help="Project-relative headless simulator script")
    args = parser.parse_args()
    if args.workers < 1:
        parser.error("--workers must be positive")
    project, engine, dataset = args.project.resolve(), args.engine.resolve(), args.output_dir.resolve()
    if not engine.is_file():
        parser.error(f"Engine not found: {engine}")
    try:
        script_path = (project / args.script).resolve()
        script_path.relative_to(project)
    except ValueError:
        parser.error("--script must remain inside the project")
    if not script_path.is_file():
        parser.error(f"Script not found: {script_path}")
    config = json.loads(args.config.read_text(encoding="utf-8-sig"))
    units = [{**job, "seeds": [seed]} for job in config["jobs"] for seed in job["seeds"]]
    if not units:
        parser.error("No seed samples configured")
    if dataset.exists():
        parser.error("Output directory already exists; choose a new dataset directory")
    dataset.mkdir(parents=True)
    started = time.monotonic()
    before = code_hashes(project, args.script)
    manifest = {"source_config": str(args.config.resolve()), "source_config_sha256": hashlib.sha256(args.config.read_bytes()).hexdigest(),
                "code_sha256": before, "script": args.script, "planned_seed_samples": len(units), "workers": min(args.workers, len(units)), "status": "running"}
    manifest_path = dataset / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    completed = []
    try:
        with ThreadPoolExecutor(max_workers=manifest["workers"]) as pool:
            futures = [pool.submit(run_shard, engine, project, dataset, index,
                                   {**config, "jobs": units[index::manifest["workers"]]}, args.worker_timeout, args.script)
                       for index in range(manifest["workers"])]
            for future in as_completed(futures):
                result = future.result()
                completed.append(result)
                print(json.dumps(result), flush=True)
        if code_hashes(project, args.script) != before:
            raise RuntimeError("Simulation sources changed during the run; refusing to merge mixed revisions")
        with (dataset / "results.jsonl").open("w", encoding="utf-8") as merged:
            for item in sorted(completed, key=lambda value: value["worker"]):
                merged.write((dataset / item["output"]).read_text(encoding="utf-8-sig"))
        manifest.update(status="complete", actual_runs=sum(item["actual_runs"] for item in completed))
    except Exception as exc:
        manifest.update(status="failed", error=str(exc))
        raise
    finally:
        manifest.update(worker_results=completed, wall_seconds=time.monotonic() - started)
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"dataset": str(dataset), "status": manifest["status"], "actual_runs": manifest["actual_runs"]}), flush=True)


if __name__ == "__main__":
    main()
