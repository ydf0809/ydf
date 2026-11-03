"""Validate the tracked preview inputs, links, naming and source integrity."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'skill/project_repro'))
from check_xpr import check


def audit_collaboration(root, errors):
    path = root / 'report/collaboration/excerpts.json'
    if not path.is_file():
        errors.append({'kind': 'collaboration_missing', 'path': path.relative_to(root).as_posix()})
        return 0
    data = json.loads(path.read_text(encoding='utf-8'))
    sources = data.get('sources', [])
    records = data.get('records', [])
    source_ids = [item.get('session_id') for item in sources]
    if len(source_ids) != len(set(source_ids)):
        errors.append({'kind': 'collaboration_duplicate_source'})
    for source in sources:
        digest = source.get('sha256_at_capture', '')
        if (not source.get('session_id') or not source.get('source_filename')
                or not isinstance(source.get('captured_bytes'), int)
                or source['captured_bytes'] <= 0
                or not re.fullmatch('[0-9a-f]{64}', digest)):
            errors.append({'kind': 'collaboration_source_schema',
                           'session_id': source.get('session_id')})
    record_ids = [item.get('id') for item in records]
    if len(record_ids) != len(set(record_ids)):
        errors.append({'kind': 'collaboration_duplicate_record'})
    for record in records:
        text = record.get('text', '')
        if (not record.get('id') or record.get('session_id') not in source_ids
                or record.get('role') not in {'user', 'assistant'}
                or not isinstance(record.get('jsonl_line'), int)
                or record['jsonl_line'] <= 0 or not text
                or re.search(r'[A-Za-z]:[\\/]', text)
                or not isinstance(record.get('redactions'), list)):
            errors.append({'kind': 'collaboration_record_schema',
                           'record_id': record.get('id')})
    return len(records)


def audit_formal_report(root, errors):
    path = root / 'report/formal_report_source.json'
    if not path.is_file():
        errors.append({'kind': 'formal_report_metadata_missing',
                       'path': path.relative_to(root).as_posix()})
        return False
    data = json.loads(path.read_text(encoding='utf-8'))
    report = root / data.get('exported', '__missing__')
    if (not report.is_file()
            or hashlib.sha256(report.read_bytes()).hexdigest()
            != data.get('exported_sha256')
            or report.stat().st_size != data.get('bytes')
            or data.get('copy_status') != 'byte_identical'):
        errors.append({'kind': 'formal_report_changed',
                       'path': data.get('exported')})
        return False
    return True


def tracked_candidates(root):
    if (root / '.git').exists():
        command = subprocess.run(['git', '-C', str(root), 'ls-files', '-z',
                                  '--cached', '--others', '--exclude-standard'],
                                 stdout=subprocess.PIPE, check=True)
        return sorted({root / item.decode('utf-8') for item in command.stdout.split(b'\0') if item})
    # A GitHub source archive has no .git directory. Audit the extracted files directly.
    ignored = {'.git', '__pycache__', '.Xil', 'generated'}
    return sorted(p for p in root.rglob('*') if p.is_file()
                  and not any(part in ignored or part.endswith(
                      ('.runs', '.gen', '.cache', '.sim', '.hw', '.ip_user_files'))
                      for part in p.relative_to(root).parts)
                  and not p.is_relative_to(root / 'build/work')
                  and not p.is_relative_to(root / 'sim/work'))

def audit(root):
    files = tracked_candidates(root)
    errors = []
    collaboration_records = audit_collaboration(root, errors)
    formal_report_checked = audit_formal_report(root, errors)
    for path in files:
        rel = path.relative_to(root)
        for part in rel.parts:
            if part in ['README.md', 'LICENSE']:
                continue
            if not re.fullmatch('[a-z0-9_.-]+', part):
                errors.append({'kind': 'filename', 'path': rel.as_posix()})
        if not path.is_file():
            errors.append({'kind': 'missing_tracked_file', 'path': rel.as_posix()})
            continue
        if path.suffix in ['.md', '.py', '.tcl', '.json', '.xpr', '.v', '.xdc', '.txt', '.rpt']:
            text = path.read_bytes().decode('utf-8', errors='replace')
            secret_pattern = (r'gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{30,}|'
                              r'sk-[A-Za-z0-9_-]{20,}|'
                              + '-----BEGIN ' + '(?:RSA |EC |OPENSSH )?' + 'PRIVATE KEY-----')
            secret = re.search(secret_pattern, text)
            if secret:
                errors.append({'kind': 'credential_pattern', 'path': rel.as_posix()})
            if path.suffix == '.md':
                for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)', text):
                    if '://' in target or target.startswith('#'):
                        continue
                    target = unquote(target.split('#')[0])
                    linked = (path.parent / target).resolve()
                    if not linked.is_relative_to(root) or not linked.exists():
                        errors.append({'kind': 'document_link', 'path': rel.as_posix(), 'target': target})
    manifest = json.loads((root / 'report/source_manifest.json').read_text())
    for item in manifest['files']:
        path = root / item['exported']
        if path.suffix == '.xpr':
            continue
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != item.get('exported_sha256', item['sha256']):
            errors.append({'kind': 'export_input_changed', 'path': item['exported']})
    xprs = [root / 'projects/merged_cam_lcd_voice_scnn/merged_cam_lcd_voice_scnn.xpr',
            root / 'projects/realfinal_min_102404/realfinal.xpr']
    checks = [check(root, path) for path in xprs]
    for item in checks:
        if not item['passed']:
            errors.append({'kind': 'xpr_dependency', 'detail': item})
    return {'files_checked': len(files),
            'collaboration_records_checked': collaboration_records,
            'formal_report_checked': formal_report_checked,
            'xpr_checks': checks,
            'errors': errors, 'passed': not errors}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = audit(args.root.resolve())
    text = json.dumps(result, ensure_ascii=True, indent=2) + chr(10)
    print(text)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
    return 0 if result['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
