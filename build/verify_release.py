"""Reject stale simulation/build/weight evidence before using a release bitstream."""
import json
from datetime import datetime
from pathlib import Path
from common import ROOT, BOARDS, input_hashes, sha256, write_json


def verify():
    errors = []
    counts = {}
    checker = json.loads((ROOT / 'report/checker_tests.json').read_text(encoding='utf-8'))
    if checker.get('status') != 'PASS':
        errors.append('checker self-tests did not pass')
    for relative, digest in checker.get('script_sha256', {}).items():
        if not (ROOT / relative).is_file() or sha256(ROOT / relative) != digest:
            errors.append('checker self-test is stale: ' + relative)
    skill = json.loads((ROOT / 'report/skill_validation.json').read_text(encoding='utf-8'))
    skill_checker = 'skill/scnn-training-pipeline/scripts/check_reference.py'
    if (skill.get('status') != 'PASS'
            or sha256(ROOT / skill_checker)
            != skill.get('script_sha256')
            or not skill.get('commands')
            or not all(item.get('passed') for item in skill['commands'])):
        errors.append('SCNN skill validation is failed or stale')
    summary = json.loads((ROOT / 'sim/results/summary.json').read_text(encoding='utf-8'))
    for board, info in BOARDS.items():
        project = ROOT / info['directory']
        report = json.loads((ROOT / 'build/reports' / board / 'manifest.json').read_text())
        current = input_hashes(board)
        tests = [item for item in summary['tests'] if item['board'] == board]
        expected = {p.stem for p in (project / info['tests']).glob('tb_*.v')}
        names = [item['test'] for item in tests]
        counts[board] = {'passed': sum(bool(item.get('passed')) for item in tests),
                         'total': len(tests)}
        if set(names) != expected or len(names) != len(expected) or not all(item['passed'] for item in tests):
            errors.append(board + ': missing, duplicate or failing test')
        if summary['source_sha256'].get(board) != current:
            errors.append(board + ': simulation source hashes are stale')
        if report.get('source_sha256') != current or not report.get('source_unchanged_during_build'):
            errors.append(board + ': build source hashes are stale')
        if report.get('release_status') != 'preview_build_candidate':
            errors.append(board + ': main build did not complete')
        if report.get('xpr_sha256') != sha256(project / info['xpr']):
            errors.append(board + ': XPR changed after build')
        for key in ('drc_errors', 'loop_warning_present', 'clock_coverage_failed'):
            if str(report.get(key)) != '0':
                errors.append(board + ': build gate failed or missing: ' + key)
        if float(report.get('wns', '-1')) < 0 or float(report.get('whs', '-1')) < 0:
            errors.append(board + ': negative setup/hold slack')
        for key in ('main_run_bit', 'bit'):
            path = ROOT / report.get(key, '__missing__')
            if not path.is_file() or sha256(path) != report.get('bit_sha256'):
                errors.append(board + ': bitstream missing or hash differs: ' + key)
        for item in tests:
            log = ROOT / item.get('log', '__missing__')
            if not log.is_file() or sha256(log) != item.get('log_sha256'):
                errors.append(board + ': simulation log missing or changed: ' + item['test'])
        for relative, digest in report.get('reports_sha256', {}).items():
            if not (ROOT / relative).is_file() or sha256(ROOT / relative) != digest:
                errors.append(board + ': build report changed: ' + relative)
    alignment = json.loads((ROOT / 'report/weight_alignment.json').read_text())
    if (alignment.get('status') != 'PASS'
            or sha256(ROOT / alignment['deployment_rom']) != alignment['deployment_rom_sha256']
            or sha256(ROOT / 'training/scnn/source_manifest.json') != alignment['training_source_manifest_sha256']):
        errors.append('weight alignment evidence is stale or failed')
    training = json.loads((ROOT / 'training/scnn/verification/run_manifest.json').read_text())
    for relative, digest in training['inputs_sha256'].items():
        if sha256(ROOT / relative) != digest:
            errors.append('training verification input changed: ' + relative)
    for relative, digest in training['outputs_sha256'].items():
        if sha256(ROOT / relative) != digest:
            errors.append('training verification output changed: ' + relative)
    if training.get('status') != 'PASS':
        errors.append('training verification did not complete')
    return {'status': 'FAIL' if errors else 'PASS', 'errors': errors, 'tests': counts,
            'completed_at': datetime.now().astimezone().isoformat(timespec='seconds'),
            'physical_board_validation': 'not_performed',
            'scope': 'Current local simulation, conversion, main-XPR build and artifact provenance.'}


if __name__ == '__main__':
    try:
        result = verify()
    except (OSError, KeyError, ValueError) as error:
        result = {'status': 'FAIL', 'errors': [str(error)]}
    write_json(ROOT / 'report/delivery_check.json', result)
    print(json.dumps(result, ensure_ascii=True, indent=2))
    raise SystemExit(0 if result['status'] == 'PASS' else 1)
