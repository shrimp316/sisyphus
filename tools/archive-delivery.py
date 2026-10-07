"""Create a complete, auditable release backup; never silently omit findings.

Run scan, then toolchain while other work continues. Run workspace only after
all writers stop, then verify. Extraction of every ZIP into one directory
restores the workspace. Git history remains on GitHub separately.
"""
import argparse
import hashlib
import json
import re
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

LIMIT = int(1.8 * 1024**3)
READ_SIZE = 1024 * 1024
TEXT_LIMIT = 2 * 1024 * 1024
EXCLUSIONS = ['.git/**', 'builds/full-upload/**']
VENDOR_DIRS = ('.tools/godot/', '.tools/export-templates/')
VENDOR_FILES = {'.tools/godot-4.5.1.zip',
                '.tools/Godot_v4.5.1-stable_export_templates.tpz',
                '.tools/SHA512-SUMS.txt'}
SECRET_PATTERNS = {
    'private-key': re.compile(r'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----'),
    'github-token': re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})\b'),
    'openai-token': re.compile(r'\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{40,}\b'),
    'aws-access-key': re.compile(r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    'slack-token': re.compile(r'\bxox[baprs]-[A-Za-z0-9-]{20,}\b'),
    'google-api-key': re.compile(r'\bAIza[A-Za-z0-9_-]{35}\b'),
    'credential-assignment': re.compile(r'''(?im)["']?(?:api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|password)["']?\s*[:=]\s*["']([^\s"']{16,})["']'''),
}


def save_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def digest(stream):
    value = hashlib.sha256()
    while block := stream.read(READ_SIZE):
        value.update(block)
    return value.hexdigest()


def file_hash(path):
    with path.open('rb') as stream:
        return digest(stream)


def inventory(root):
    files, directories = [], []
    def walk(folder):
        for path in sorted(folder.iterdir(), key=lambda p: p.name):
            rel = path.relative_to(root).as_posix()
            if rel == '.git' or rel == 'builds/full-upload':
                continue
            if path.is_symlink() or (hasattr(path, 'is_junction') and path.is_junction()):
                raise RuntimeError('Linked path requires explicit review: ' + rel)
            if path.is_dir():
                directories.append(rel)
                walk(path)
            elif path.is_file():
                files.append((rel, path))
            else:
                raise RuntimeError('Unsupported filesystem entry: ' + rel)
    walk(root)
    return files, directories


def scan(files):
    findings = []
    for rel, path in files:
        lower = path.name.lower()
        sensitive = (lower in {'credentials', 'credentials.json', 'auth.json', 'secrets.json', 'id_rsa', 'id_ed25519', '.netrc', '.npmrc', '.pypirc'}
                     or lower == '.env' or lower.startswith('.env.')
                     or path.suffix.lower() in {'.pem', '.key', '.p12', '.pfx', '.keystore'})
        if sensitive:
            findings.append({'file': rel, 'rule': 'sensitive-filename'})
        if path.stat().st_size > TEXT_LIMIT:
            continue
        raw = path.read_bytes()
        if b'\0' in raw[:8192]:
            continue
        try:
            text = raw.decode('utf-8-sig')
        except UnicodeDecodeError:
            continue
        for rule, pattern in SECRET_PATTERNS.items():
            if pattern.search(text):
                findings.append({'file': rel, 'rule': rule})
    return findings


def is_toolchain(rel):
    return rel in VENDOR_FILES or rel.startswith(VENDOR_DIRS)


def make_entries(files, group):
    entries = []
    for rel, path in files:
        if is_toolchain(rel) != (group == 'toolchain'):
            continue
        before = path.stat()
        sha = file_hash(path)
        after = path.stat()
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
            raise RuntimeError('File changed while hashing: ' + rel)
        entries.append({'path': rel, 'size': after.st_size, 'sha256': sha})
    return entries


def write_archives(root, out, group, entries):
    batches, batch, size = [], [], 0
    for entry in entries:
        cost = entry['size'] + len(entry['path'].encode('utf-8')) * 2 + 512
        if cost > LIMIT:
            raise RuntimeError('Single file exceeds archive budget: ' + entry['path'])
        if batch and size + cost > LIMIT:
            batches.append(batch)
            batch, size = [], 0
        batch.append(entry)
        size += cost
    if batch:
        batches.append(batch)
    archives = []
    for number, batch in enumerate(batches, 1):
        name = f'SISYPHUS-{group.title()}' + (f'-{number:02}' if len(batches) > 1 else '') + '.zip'
        destination = out / name
        temporary = destination.with_suffix('.zip.partial')
        with zipfile.ZipFile(temporary, 'w', allowZip64=True) as archive:
            for entry in batch:
                path = root / entry['path']
                info = zipfile.ZipInfo.from_file(path, arcname=entry['path'])
                info.compress_type = zipfile.ZIP_STORED if path.suffix.lower() in {'.zip', '.tpz', '.png', '.jpg', '.jpeg', '.ogg', '.mp3', '.webp'} else zipfile.ZIP_DEFLATED
                info._compresslevel = 1
                hasher = hashlib.sha256()
                actual = 0
                with path.open('rb') as source, archive.open(info, 'w', force_zip64=True) as target:
                    while block := source.read(READ_SIZE):
                        hasher.update(block)
                        actual += len(block)
                        target.write(block)
                if actual != entry['size'] or hasher.hexdigest() != entry['sha256']:
                    raise RuntimeError('File changed during archive creation: ' + entry['path'])
                entry['archive'] = name
        if temporary.stat().st_size >= LIMIT:
            raise RuntimeError('Archive exceeds safety budget: ' + name)
        temporary.replace(destination)
        archives.append({'file': name, 'size': destination.stat().st_size, 'sha256': file_hash(destination)})
        print(f'{name}: {len(batch)} files, {destination.stat().st_size} bytes', flush=True)
    return archives


def verify(root, out):
    manifest = json.loads((out / 'snapshot-manifest.json').read_text(encoding='utf-8'))
    expected = {entry['path']: entry for entry in manifest['entries']}
    current, _ = inventory(root)
    if {rel for rel, _ in current} != set(expected):
        raise RuntimeError('Workspace file inventory has changed since snapshot')
    for rel, path in current:
        if path.stat().st_size != expected[rel]['size'] or file_hash(path) != expected[rel]['sha256']:
            raise RuntimeError('Workspace content differs from snapshot: ' + rel)
    seen = set()
    for artifact in manifest['archives']:
        path = out / artifact['file']
        if path.stat().st_size != artifact['size'] or file_hash(path) != artifact['sha256']:
            raise RuntimeError('Archive hash mismatch: ' + artifact['file'])
        with zipfile.ZipFile(path) as archive:
            for info in archive.infolist():
                entry = expected.get(info.filename)
                if entry is None or info.filename in seen or entry['archive'] != artifact['file']:
                    raise RuntimeError('Unexpected or duplicate archived file: ' + info.filename)
                with archive.open(info) as stream:
                    if info.file_size != entry['size'] or digest(stream) != entry['sha256']:
                        raise RuntimeError('Archived content mismatch: ' + info.filename)
                seen.add(info.filename)
    if seen != set(expected):
        raise RuntimeError('Archive coverage is incomplete')
    report = {'status': 'PASS', 'files': len(seen), 'archives': len(manifest['archives']),
              'all_workspace_files_match': True, 'all_archived_hashes_match': True,
              'exclusions': EXCLUSIONS}
    save_json(out / 'verification.json', report)
    print(json.dumps(report), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--phase', choices=['scan', 'toolchain', 'workspace', 'verify'], default='scan')
    args = parser.parse_args()
    root = args.root.resolve()
    out = root / 'builds/full-upload'
    out.mkdir(parents=True, exist_ok=True)
    if args.phase == 'verify':
        verify(root, out)
        return
    files, directories = inventory(root)
    findings = scan(files)
    save_json(out / 'security-scan.json', {'small_text_limit_bytes': TEXT_LIMIT, 'files_checked': len(files),
              'exclusions': EXCLUSIONS, 'findings': findings,
              'scope': 'Sensitive filenames plus UTF-8 files up to 2 MiB; no credential values emitted. Binary and nested archive contents are not text-scanned.'})
    if findings:
        print(f'STOP: {len(findings)} security findings. Review builds/full-upload/security-scan.json; no new archive created.')
        sys.exit(2)
    print(f'Security scan PASS: {len(files)} files; no paths silently excluded.', flush=True)
    if args.phase == 'scan':
        return
    group = args.phase
    entries = make_entries(files, group)
    archives = write_archives(root, out, group, entries)
    save_json(out / f'{group}-manifest.json', {'entries': entries, 'archives': archives})
    if group == 'workspace':
        toolchain = json.loads((out / 'toolchain-manifest.json').read_text(encoding='utf-8'))
        current_tools = make_entries(files, 'toolchain')
        if {(e['path'], e['size'], e['sha256']) for e in current_tools} != {(e['path'], e['size'], e['sha256']) for e in toolchain['entries']}:
            raise RuntimeError('Toolchain changed; rebuild toolchain archive before final snapshot')
        all_entries = sorted(entries + toolchain['entries'], key=lambda e: e['path'])
        if {e['path'] for e in all_entries} != {rel for rel, _ in files}:
            raise RuntimeError('Snapshot file coverage mismatch')
        manifest = {'schema_version': 1, 'created_at': datetime.now(timezone.utc).isoformat(),
                    'exclusions': EXCLUSIONS, 'file_count': len(all_entries),
                    'total_uncompressed_bytes': sum(e['size'] for e in all_entries),
                    'directories': directories, 'entries': all_entries,
                    'archives': archives + toolchain['archives']}
        save_json(out / 'snapshot-manifest.json', manifest)
        (out / 'SHA256SUMS.txt').write_text(''.join(f"{e['sha256']}  {e['file']}\n" for e in manifest['archives']) + f"{file_hash(out / 'snapshot-manifest.json')}  snapshot-manifest.json\n", encoding='utf-8')
        print(f'Snapshot prepared: {len(all_entries)} files; run --phase verify.', flush=True)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
