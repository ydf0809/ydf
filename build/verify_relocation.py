"""Archive the Git index, extract to a different path and rerun real checks."""
import argparse
from datetime import datetime
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

from common import BOARDS, ROOT, environment, sha256, write_json


def run(command, cwd, root_label, timeout=None):
    print('+ ' + ' '.join(map(str, command)), flush=True)
    result = subprocess.run(
        [str(item) for item in command],
        cwd=cwd,
        env=environment(),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        encoding='utf-8',
        errors='replace',
        timeout=timeout,
    )
    text = result.stdout.replace(str(root_label), '[relocated]')
    if text:
        print(text, end='' if text.endswith('\n') else '\n', flush=True)
    if result.returncode:
        raise RuntimeError('Command failed with exit code ' + str(result.returncode))
    return text


def git_output(*args):
    result = subprocess.run(
        ['git', '-C', str(ROOT), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vivado-bin', required=True)
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--build-timeout', type=int, default=7200)
    args = parser.parse_args()

    unstaged = subprocess.run(
        ['git', '-C', str(ROOT), 'diff', '--quiet'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    if unstaged.returncode:
        raise SystemExit('Stage tracked changes before relocation verification.')

    tree = git_output('write-tree').decode('ascii').strip()
    with tempfile.TemporaryDirectory(prefix='ydf_relocation_') as temp:
        temp = Path(temp)
        archive = temp / 'ydf-index.zip'
        subprocess.run(
            ['git', '-C', str(ROOT), 'archive', '--format=zip',
             '--output=' + str(archive), tree],
            check=True,
        )
        relocated = temp / 'path with spaces' / 'ydf'
        relocated.mkdir(parents=True)
        with zipfile.ZipFile(archive) as package:
            package.extractall(relocated)

        run(
            [sys.executable, 'build/verify_repository.py',
             '--root', relocated, '--output',
             relocated / 'report/repository_check_relocation.json'],
            relocated,
            relocated,
        )
        run(
            [sys.executable, 'sim/run.py',
             '--vivado-bin', args.vivado_bin, '--board', 'all'],
            relocated,
            relocated,
        )
        run(
            [sys.executable, 'build/run.py',
             '--vivado-bin', args.vivado_bin, '--board', 'all',
             '--jobs', str(args.jobs)],
            relocated,
            relocated,
            timeout=args.build_timeout,
        )
        run(
            [sys.executable, 'build/verify_release.py'],
            relocated,
            relocated,
        )

        relocation_check = json.loads(
            (relocated / 'report/repository_check_relocation.json').read_text(
                encoding='utf-8'))
        simulation = json.loads(
            (relocated / 'sim/results/summary.json').read_text(encoding='utf-8'))
        delivery = json.loads(
            (relocated / 'report/delivery_check.json').read_text(encoding='utf-8'))
        boards = {}
        for board in BOARDS:
            manifest = json.loads(
                (relocated / 'build/reports' / board / 'manifest.json').read_text(
                    encoding='utf-8'))
            boards[board] = {
                key: manifest.get(key)
                for key in (
                    'release_status', 'top', 'part', 'wns', 'whs',
                    'drc_errors', 'loop_warning_present',
                    'clock_coverage_failed', 'source_unchanged_during_build',
                    'bit_bytes', 'bit_sha256', 'elapsed_seconds',
                )
            }
            boards[board]['source_sha256'] = manifest.get('source_sha256', {})

        simulation_result = {
            'status': (
                'PASS'
                if simulation.get('tests')
                and all(item.get('passed') for item in simulation['tests'])
                else 'FAIL'
            ),
            'completed_at': datetime.now().astimezone().isoformat(),
            'git_tree': tree,
            'archive_sha256': sha256(archive),
            'physical_validation': 'not_performed',
            **simulation,
        }
        summary = {
            'status': (
                'PASS'
                if relocation_check.get('passed') and delivery.get('status') == 'PASS'
                and simulation_result['status'] == 'PASS'
                and all(item['release_status'] == 'preview_build_candidate'
                        for item in boards.values())
                else 'FAIL'
            ),
            'completed_at': datetime.now().astimezone().isoformat(),
            'git_tree': tree,
            'archive_sha256': sha256(archive),
            'archive_size_bytes': archive.stat().st_size,
            'relocated_repository_check': {
                'passed': relocation_check.get('passed'),
                'files_checked': relocation_check.get('files_checked'),
                'errors': relocation_check.get('errors', []),
            },
            'relocated_simulation': {
                'passed': sum(bool(item.get('passed'))
                              for item in simulation.get('tests', [])),
                'total': len(simulation.get('tests', [])),
            },
            'builds': boards,
            'relocated_delivery_check': delivery,
            'physical_validation': 'not_performed',
            'scope': (
                'Git-index archive extracted to a different path with spaces; '
                'real Vivado simulation and both main-XPR builds.'
            ),
        }

        write_json(ROOT / 'report/repository_check_relocation.json',
                   relocation_check)
        write_json(ROOT / 'report/relocation_simulation.json',
                   simulation_result)
        write_json(ROOT / 'report/relocation.json', summary)
        print(json.dumps(summary, ensure_ascii=True, indent=2))
        return 0 if summary['status'] == 'PASS' else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError) as error:
        result = {
            'status': 'FAIL',
            'completed_at': datetime.now().astimezone().isoformat(),
            'error': str(error),
            'physical_validation': 'not_performed',
        }
        write_json(ROOT / 'report/relocation.json', result)
        write_json(ROOT / 'report/relocation_simulation.json', result)
        print(json.dumps(result, ensure_ascii=True, indent=2))
        raise SystemExit(1)
