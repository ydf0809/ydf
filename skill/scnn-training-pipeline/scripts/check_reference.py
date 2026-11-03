"""Check the SCNN reference tree and optionally run its verification commands."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys


REQUIRED_FILES = [
    'model.py',
    'train.py',
    'convert_weights.py',
    'verify.py',
    'model_spec.json',
    'requirements.txt',
    'parameters/final_engine_weights.json',
    'assets/reference_frame.mem',
]

WEIGHT_FILES = [
    'weights/0/conv1_weights.coe',
    'weights/1/conv1_weights.mem',
    'weights/2/conv2_weights.coe',
    'weights/3/conv2_weights.mem',
    'weights/4/fc_weights_0.coe',
    'weights/5/fc_weights_0.mem',
    'weights/6/fc_weights_1.coe',
    'weights/7/fc_weights_1.mem',
]

EXPECTED_SPEC = {
    'input_shape_chw': [3, 64, 64],
    'input_channel_order': ['B', 'G', 'R'],
    'class_names': ['not_drone', 'drone'],
    'kernel_size': 3,
    'padding': 1,
    'bias': False,
    'weight_bits': 16,
    'weight_fraction_bits': 12,
    'membrane_bits': 26,
    'time_steps': 50,
    'lif_tau': 2,
    'lif_threshold_q': 4096,
    'lif_reset_q': 0,
}


def run(command, cwd, timeout):
    display = [Path(command[0]).name, *command[1:]]
    print('+ ' + ' '.join(display), flush=True)
    completed = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        encoding='utf-8',
        errors='replace',
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    print(completed.stdout, end='' if completed.stdout.endswith('\n') else '\n')
    return {
        'command': display,
        'exit_code': completed.returncode,
        'passed': completed.returncode == 0,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path)
    parser.add_argument('--python', default=sys.executable)
    parser.add_argument('--require-record', action='store_true')
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--timeout', type=int, default=900)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()

    root = (args.root or Path(__file__).resolve().parents[3] / 'training/scnn').resolve()
    errors = []
    for relative in REQUIRED_FILES + WEIGHT_FILES:
        if not (root / relative).is_file():
            errors.append({'kind': 'missing', 'path': relative})

    spec = {}
    spec_path = root / 'model_spec.json'
    if spec_path.is_file():
        spec = json.loads(spec_path.read_text(encoding='utf-8'))
        for key, expected in EXPECTED_SPEC.items():
            if spec.get(key) != expected:
                errors.append({
                    'kind': 'model_spec_mismatch',
                    'key': key,
                    'expected': expected,
                    'actual': spec.get(key),
                })

    manifest_path = root / 'verification/run_manifest.json'
    manifest = {}
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        if manifest.get('status') != 'PASS':
            errors.append({'kind': 'verification_not_pass',
                           'status': manifest.get('status')})
    elif args.require_record:
        errors.append({'kind': 'verification_record_missing'})

    commands = []
    if args.run:
        commands.append(run([args.python, 'verify.py'], root, args.timeout))
        commands.append(run([args.python, 'train.py', '--smoke-test'],
                            root, args.timeout))
        if not all(item['passed'] for item in commands):
            errors.append({'kind': 'command_failed'})

    try:
        reference_label = root.relative_to(Path.cwd().resolve()).as_posix()
    except ValueError:
        reference_label = root.name
    result = {
        'status': 'PASS' if not errors else 'FAIL',
        'completed_at': datetime.now().astimezone().isoformat(),
        'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'reference_root': reference_label,
        'model_spec': {
            key: spec.get(key)
            for key in EXPECTED_SPEC
        },
        'verification_record': manifest.get('status'),
        'commands': commands,
        'errors': errors,
    }
    text = json.dumps(result, ensure_ascii=True, indent=2) + '\n'
    print(text)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
