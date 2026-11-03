"""Exercise the result and XPR checkers with positive and negative fixtures."""
from datetime import datetime
import importlib.util
import json
from pathlib import Path
import tempfile
import xml.etree.ElementTree as ET

from common import ROOT, sha256, write_json

SIM_RUNNER = ROOT / 'sim/run.py'
XPR_CHECKER = ROOT / 'skill/project_repro/check_xpr.py'


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def judge_cases():
    judge_output = load_module('sim_runner', SIM_RUNNER).judge_output
    cases = [
        ('complete', 'PASS complete\n', ['PASS'], 0, True),
        ('failure_after_pass', 'PASS complete\nFAIL: mismatch\n', ['PASS'], 0, False),
        ('fatal_after_pass', 'PASS complete\nFATAL: stopped\n', ['PASS'], 0, False),
        ('error_after_pass', 'PASS complete\nERROR: stopped\n', ['PASS'], 0, False),
        ('numeric_fail_count', 'PASS complete\nRESULT: 2 checks failed\n',
         ['PASS'], 0, False),
        ('missing_completion', 'SIMULATION STARTED\n', ['PASS'], 0, False),
        ('nonzero_exit', 'PASS complete\n', ['PASS'], 1, False),
        ('not_line_marker', 'prefix PASS complete\n', ['PASS'], 0, False),
    ]
    records = []
    for name, text, prefixes, status, expected in cases:
        actual, markers, failures = judge_output(text, prefixes, status)
        records.append({
            'case': name,
            'expected_accept': expected,
            'actual_accept': actual,
            'pass_markers': markers,
            'failure_markers': failures,
            'passed': actual == expected,
        })
    return records


def xpr_cases():
    checker = load_module('xpr_checker', XPR_CHECKER).check
    records = []
    with tempfile.TemporaryDirectory(prefix='check_xpr_') as temp:
        temp = Path(temp)
        root = temp / 'project'
        (root / 'rtl').mkdir(parents=True)
        (root / 'rtl/good.v').write_text('module good; endmodule\n', encoding='utf-8')
        (temp / 'outside.v').write_text('module outside; endmodule\n', encoding='utf-8')

        def write_xpr(name, path):
            project = ET.Element('Project')
            fileset = ET.SubElement(project, 'FileSet', Name='sources_1')
            ET.SubElement(fileset, 'File', Path=path)
            xpr = root / name
            ET.ElementTree(project).write(xpr, encoding='utf-8', xml_declaration=True)
            return xpr

        fixtures = [
            ('contained_xpr_source_accepted', '$PPRDIR/rtl/good.v', True, None),
            ('missing_xpr_source_rejected', '$PPRDIR/rtl/missing.v', False, 'missing'),
            ('outside_xpr_source_rejected', '$PPRDIR/../outside.v', False, 'outside'),
        ]
        for name, path, expected, category in fixtures:
            result = checker(root, write_xpr(name + '.xpr', path))
            category_ok = category is None or bool(result[category])
            records.append({
                'case': name,
                'expected_accept': expected,
                'actual_accept': result['passed'],
                'failure_category': category,
                'failure_present': category_ok,
                'passed': result['passed'] == expected and category_ok,
            })
    return records


def main():
    cases = judge_cases() + xpr_cases()
    result = {
        'status': 'PASS' if all(item['passed'] for item in cases) else 'FAIL',
        'completed_at': datetime.now().astimezone().isoformat(),
        'cases': cases,
        'script_sha256': {
            path.relative_to(ROOT).as_posix(): sha256(path)
            for path in (ROOT / 'build/test_checkers.py', SIM_RUNNER, XPR_CHECKER)
        },
    }
    write_json(ROOT / 'report/checker_tests.json', result)
    print(json.dumps(result, ensure_ascii=True, indent=2))
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
