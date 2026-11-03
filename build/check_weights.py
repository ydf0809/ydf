"""Compare canonical SCNN exports with the ROM registered in the upper main XPR."""
import argparse
from datetime import datetime
import json
from pathlib import Path
import sys
import tempfile
import xml.etree.ElementTree as ET

from common import ROOT, BOARDS, sha256, write_json

TRAINING = ROOT / 'training/scnn'
sys.path.insert(0, str(TRAINING))
from convert_weights import (LAYERS, decode, export, packed_words,
                             read_embedded_rom, read_payload, read_words)


def check():
    upper = ROOT / BOARDS['upper']['directory']
    rom = upper / 'rtl/drone_data_roms.v'
    xpr = upper / BOARDS['upper']['xpr']
    registered = [node.get('Path', '') for node in
                  ET.parse(xpr).findall(".//FileSet[@Name='sources_1']/File")]
    if '$PPRDIR/rtl/drone_data_roms.v' not in registered:
        raise ValueError('The deployed weight ROM is not registered in the main XPR.')
    payload = decode(TRAINING / 'weights', 'both')
    for relative in ('recovered_weights.json', 'parameters/final_engine_weights.json'):
        if read_payload(TRAINING / relative)['tensors'] != payload['tensors']:
            raise ValueError('Canonical parameters disagree: ' + relative)
    words = packed_words(payload)
    generated = TRAINING / 'generated'
    generated.mkdir(parents=True, exist_ok=True)
    records = []
    with tempfile.TemporaryDirectory(prefix='deployment_', dir=generated) as temp:
        temp = Path(temp)
        export(payload, temp / 'weights', temp / 'rom.v')
        for name, coe, mem, width, depth in LAYERS:
            variants = [read_words(temp / 'weights' / coe, width, depth, 'coe'),
                        read_words(temp / 'weights' / mem, width, depth, 'mem'),
                        read_embedded_rom(temp / 'rom.v', name, width, depth),
                        read_embedded_rom(rom, name, width, depth)]
            if any(item != words[name] for item in variants):
                raise ValueError('Generated COE/MEM/ROM differs from deployment: ' + name)
            records.append({'module': 'drone_' + name + '_rom',
                            'word_bits': width, 'words': depth, 'matches': True})
        frame = read_words(TRAINING / 'assets/reference_frame.mem', 24, 4096, 'mem')
        if (frame != read_words(upper / 'reference_frame.mem', 24, 4096, 'mem')
                or frame != read_embedded_rom(rom, 'frame', 24, 4096)
                or frame != read_embedded_rom(temp / 'rom.v', 'frame', 24, 4096)):
            raise ValueError('Reference-frame ROM differs from the bundled input.')
        records.append({'module': 'drone_frame_rom', 'word_bits': 24,
                        'words': 4096, 'matches': True})
    return {'status': 'PASS', 'completed_at': datetime.now().astimezone().isoformat(),
            'canonical_parameters': 3416, 'roms': records,
            'main_xpr': xpr.relative_to(ROOT).as_posix(),
            'deployment_rom': rom.relative_to(ROOT).as_posix(),
            'deployment_rom_sha256': sha256(rom),
            'training_source_manifest_sha256': sha256(TRAINING / 'source_manifest.json'),
            'scope': 'Weight data and registered source; not dataset accuracy or hardware validation.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'report/weight_alignment.json')
    args = parser.parse_args()
    try:
        result = check()
    except (ValueError, OSError, KeyError) as error:
        result = {'status': 'FAIL', 'error': str(error)}
    write_json(args.output, result)
    print(json.dumps(result, ensure_ascii=True, indent=2))
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
