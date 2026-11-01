"""Check that XPR file references exist inside a movable project root."""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

def check(root, xpr):
    root = Path(root).resolve()
    xpr = Path(xpr).resolve()
    tree = ET.parse(xpr)
    macros = {'$PPRDIR': str(xpr.parent),
              '$PSRCDIR': str(xpr.parent / (xpr.stem + '.srcs')),
              '$PGENDIR': str(xpr.parent / (xpr.stem + '.gen')),
              '$PRUNDIR': str(xpr.parent / (xpr.stem + '.runs'))}
    result = {'xpr': xpr.relative_to(root).as_posix(),
              'references': 0, 'missing': [], 'outside': [], 'unresolved': []}
    for node in tree.iter('File'):
        raw = node.get('Path')
        if not raw:
            continue
        result['references'] += 1
        value = raw
        for key, replacement in macros.items():
            value = value.replace(key, replacement)
        if '$' in value:
            result['unresolved'].append(raw)
            continue
        path = Path(value)
        if not path.is_absolute():
            path = xpr.parent / path
        path = path.resolve()
        if not path.is_relative_to(root):
            result['outside'].append(raw)
        if not path.is_file():
            result['missing'].append(raw)
    result['passed'] = not any(result[key] for key in ['missing', 'outside', 'unresolved'])
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--xpr', type=Path, action='append', required=True)
    args = parser.parse_args()
    results = [check(args.root, args.root / path) for path in args.xpr]
    print(json.dumps(results, ensure_ascii=True, indent=2))
    return 0 if all(item['passed'] for item in results) else 1

if __name__ == '__main__':
    raise SystemExit(main())
