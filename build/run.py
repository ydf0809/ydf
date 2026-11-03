"""Build the main XPR for each selected board, without editing production RTL."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path
import shutil
import time
import xml.etree.ElementTree as ET
from common import (ROOT, BOARDS, execute, input_hashes, public_text, sha256,
                    tool_bin, write_json)

def build(board, bin_dir, jobs):
    info = BOARDS[board]
    xpr = ROOT / info['directory'] / info['xpr']
    output = ROOT / 'build/reports' / board
    work = ROOT / 'build/work' / board
    output.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    initial = input_hashes(board)
    started = time.monotonic()
    result = {'board': board, 'xpr': xpr.relative_to(ROOT).as_posix(),
              'source_sha256': initial, 'physical_validation': 'not_performed'}
    write_json(output / 'manifest.json', {**result, 'release_status': 'building'})
    for name in ['metrics.txt', 'bit_path.txt']:
        stale = output / name
        if stale.exists():
            stale.unlink()
    print('BUILD START ' + board, flush=True)
    try:
        status, text = execute(bin_dir, 'vivado',
            ['-mode', 'batch', '-source', ROOT / 'build/project.tcl',
             '-tclargs', xpr, output, jobs], work, timeout=7200)
        (work / 'console.txt').write_text(text, encoding='utf-8')
        (output / 'console.txt').write_text(public_text(text), encoding='utf-8')
        result['exit_code'] = status
        result['source_unchanged_during_build'] = initial == input_hashes(board)
        metrics = output / 'metrics.txt'
        if metrics.exists():
            result.update(line.split('=', 1) for line in metrics.read_text().splitlines()
                          if '=' in line)
        method = output / 'methodology.rpt'
        result['critical_warnings'] = []
        if method.exists():
            result['critical_warnings'] = [line.strip() for line in
                method.read_text(errors='replace').splitlines()
                if 'Critical Warning' in line and line.lstrip().startswith('|')]
        if (status != 0 or 'PREVIEW_BUILD_PASS ' + info['top'] not in text
                or not result['source_unchanged_during_build']):
            raise RuntimeError('Build failed or a design input changed; see build/work.')
        path_record = output / 'bit_path.txt'
        bit = Path(path_record.read_text().strip())
        release = ROOT / 'board/bitstreams' / board / bit.name
        release.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(bit, release)
        result.update(main_run_bit=bit.relative_to(ROOT).as_posix(),
                      bit=release.relative_to(ROOT).as_posix(),
                      bit_sha256=sha256(bit), bit_bytes=bit.stat().st_size,
                      release_copy_matches_main_run=sha256(bit) == sha256(release),
                      release_status='preview_build_candidate')
        if not result['release_copy_matches_main_run']:
            raise RuntimeError('Published bit does not match its main run.')
        path_record.unlink()
    except Exception as exc:
        result.update(release_status='build_failed', error=public_text(str(exc)))
    finally:
        result['completed_at'] = datetime.now().astimezone().isoformat(timespec='seconds')
        result['elapsed_seconds'] = round(time.monotonic() - started, 1)
        for report in output.glob('*.rpt'):
            report.write_text(public_text(report.read_text(errors='replace')),
                              encoding='utf-8')
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
        tree = ET.parse(xpr, parser=parser)
        tree.getroot().set('Path', xpr.name)
        for node in tree.iter('Run'):
            if 'IncrementalCheckpoint' in node.attrib:
                node.set('IncrementalCheckpoint', '')
        tree.write(xpr, encoding='utf-8', xml_declaration=True)
        result['xpr_sha256'] = sha256(xpr)
        result['reports_sha256'] = {
            path.relative_to(ROOT).as_posix(): sha256(path)
            for path in sorted(output.iterdir())
            if path.is_file() and path.suffix in {'.rpt', '.txt'}
        }
        write_json(output / 'manifest.json', result)
    print('BUILD ' + board + ': ' + result['release_status'], flush=True)
    return result['release_status'] == 'preview_build_candidate'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--board', choices=['all', *BOARDS], default='all')
    parser.add_argument('--vivado-bin')
    parser.add_argument('--jobs', type=int, default=4)
    args = parser.parse_args()
    boards = list(BOARDS) if args.board == 'all' else [args.board]
    bin_dir = tool_bin(args.vivado_bin)
    with ThreadPoolExecutor(max_workers=len(boards)) as pool:
        passed = list(pool.map(lambda board: build(board, bin_dir, args.jobs), boards))
    return 0 if all(passed) else 1

if __name__ == '__main__':
    raise SystemExit(main())
