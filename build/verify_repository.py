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
    return {'files_checked': len(files), 'xpr_checks': checks,
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
