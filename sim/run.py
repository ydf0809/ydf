"""Run the original testbenches and retain explicit outcomes, including failures."""
import argparse
from datetime import datetime
from pathlib import Path
import re
import shutil
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'build'))
from common import ROOT, BOARDS, execute, input_hashes, public_text, sha256, tool_bin, write_json

def judge_output(text, expected_prefixes, status):
    lines = text.splitlines()
    markers = [line.strip() for line in lines
               if any(prefix and line.strip().startswith(prefix.strip())
                      for prefix in expected_prefixes)]
    failure_pattern = re.compile(
        r'^\s*(?:\[FAIL\]|(?:FAIL|FAILED|FATAL|ERROR|Fatal|Error)\s*[: ]|'
        r'.*TEST:\s*FAIL|==.*\bFAIL\b)|'
        r'^\s*RESULT:\s*[1-9][0-9]*\s+checks?\s+failed', re.IGNORECASE)
    failures = [line.strip() for line in lines if failure_pattern.search(line)]
    return status == 0 and bool(markers) and not failures, markers, failures

def test_dependencies(test, rtl):
    def uncomment(path):
        text = path.read_bytes().decode('utf-8-sig', errors='replace')
        return re.sub(r'//[^\n]*|/\*.*?\*/', '', text, flags=re.DOTALL)
    texts = {path: uncomment(path) for path in [*rtl, test]}
    modules = {}
    for path in rtl:
        for name in re.findall(r'\bmodule\s+([a-zA-Z_][a-zA-Z0-9_$]*)', texts[path]):
            modules[name] = path
    patterns = {name: re.compile(r'\b' + re.escape(name) +
        r'\s*(?:#\s*\([^;]*?\)\s*)?[a-zA-Z_][a-zA-Z0-9_$]*\s*\(', re.DOTALL)
        for name in modules}
    pending = [test]
    selected = set()
    while pending:
        path = pending.pop()
        if path in selected:
            continue
        selected.add(path)
        for name, pattern in patterns.items():
            if pattern.search(texts[path]) and modules[name] not in selected:
                pending.append(modules[name])
    return sorted(selected - {test}) + [test]

def run_board(board, bin_dir, timeout):
    info = BOARDS[board]
    project = ROOT / info['directory']
    initial = input_hashes(board)
    rtl = sorted((project / info['rtl']).rglob('*.v'))
    tests = sorted((project / info['tests']).glob('tb_*.v'))
    rtl += sorted(p for p in (project / info['tests']).rglob('*.v')
                  if not p.name.startswith('tb_'))
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    work = ROOT / 'sim/work' / board / stamp
    work.mkdir(parents=True, exist_ok=True)
    output = ROOT / 'sim/results'
    output.mkdir(parents=True, exist_ok=True)
    weights = project / 'weights'
    if weights.exists():
        shutil.copytree(weights, work / 'weights', dirs_exist_ok=True)
    reference = project / 'reference_frame.mem'
    if reference.exists():
        shutil.copyfile(reference, work / reference.name)
    flags = ['--sv'] if info['system_verilog'] else []
    results = []
    for test in tests:
        name = test.stem
        case_work = work / name
        case_work.mkdir(parents=True, exist_ok=True)
        if weights.exists():
            shutil.copytree(weights, case_work / 'weights', dirs_exist_ok=True)
        if reference.exists():
            shutil.copyfile(reference, case_work / reference.name)
        dependencies = test_dependencies(test, rtl)
        if board == 'lower':
            dependencies.append(bin_dir.parent / 'data/verilog/src/glbl.v')
        result = {'board': board, 'test': name, 'passed': False,
                  'source': test.relative_to(ROOT).as_posix(), 'stage': 'compile',
                  'dependencies': [p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT)
                                   else '[vivado]/data/verilog/src/glbl.v'
                                   for p in dependencies]}
        log = ''
        try:
            compile_code, compile_text = execute(bin_dir, 'xvlog',
                flags + list(map(str, dependencies)), case_work, timeout)
            log = compile_text
            if compile_code:
                result['exit_code'] = compile_code
            else:
                result['stage'] = 'elaborate'
                snapshot = board + '_' + name
                status, text = execute(bin_dir, 'xelab',
                    ['-L', 'unisims_ver', '--timescale', '1ns/1ps',
                     name, *(['glbl'] if board == 'lower' else []),
                     '-s', snapshot], case_work, timeout)
                log += chr(10) + text
                result['exit_code'] = status
                if status == 0:
                    result['stage'] = 'simulate'
                    control = case_work / 'run_all.tcl'
                    control.write_text('run all' + chr(10) + 'quit' + chr(10), encoding='utf-8')
                    status, text = execute(bin_dir, 'xsim',
                        [snapshot, '-tclbatch', control.name], case_work, timeout)
                    log += chr(10) + text
                    source = test.read_bytes().decode('utf-8-sig', errors='replace')
                    expected = re.findall(r'\$display\s*\(\s*"([^"]*pass[^"]*)"',
                                          source, re.IGNORECASE)
                    prefixes = [value.split('%')[0] for value in expected]
                    passed, markers, failures = judge_output(text, prefixes, status)
                    result.update(exit_code=status, pass_markers=markers,
                                  failure_markers=failures, passed=passed)
                    if 'EXCEPTION_ACCESS_VIOLATION' in text or 'Could not open file mapping object' in text:
                        result['stage'] = 'simulator_error'
        except subprocess.TimeoutExpired:
            result.update(stage='timeout', error='Simulator exceeded configured timeout.')
            log += chr(10) + result['error']
        log_path = output / (board + '_' + name + '.txt')
        log_path.write_text(public_text(log), encoding='utf-8')
        result.update(log=log_path.relative_to(ROOT).as_posix(), log_sha256=sha256(log_path))
        result['inputs_unchanged'] = initial == input_hashes(board)
        result['passed'] = result['passed'] and result['inputs_unchanged']
        results.append(result)
        print(board + '/' + name + ': ' + ('PASS' if result['passed'] else 'FAIL (' + result['stage'] + ')'), flush=True)
    return results

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--board', choices=['all', *BOARDS], default='all')
    parser.add_argument('--vivado-bin')
    parser.add_argument('--timeout', type=int, default=240)
    args = parser.parse_args()
    boards = list(BOARDS) if args.board == 'all' else [args.board]
    groups = [run_board(board, tool_bin(args.vivado_bin), args.timeout) for board in boards]
    results = [item for group in groups for item in group]
    output = 'summary.json' if args.board == 'all' else 'summary_' + args.board + '.json'
    write_json(ROOT / 'sim/results' / output, {
        'completed_at': datetime.now().astimezone().isoformat(timespec='seconds'),
        'source_sha256': {board: input_hashes(board) for board in boards},
        'physical_validation': 'not_performed', 'tests': results})
    print('SIMULATION: %d/%d PASS' % (sum(r['passed'] for r in results), len(results)), flush=True)
    return 0 if results and all(r['passed'] for r in results) else 1

if __name__ == '__main__':
    raise SystemExit(main())
