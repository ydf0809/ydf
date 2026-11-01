"""Export explicit active PACKAGE_PIN/IOSTANDARD assignments from the XDCs."""
import csv
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    'upper': 'projects/merged_cam_lcd_voice_scnn/constraints/top.xdc',
    'lower': 'projects/realfinal_min_102404/realfinal.srcs/constrs_1/new/10086.xdc',
}

def main():
    rows = []
    for board, relative in SOURCES.items():
        values = {}
        text = (ROOT / relative).read_bytes().decode('utf-8-sig', errors='replace')
        for number, raw in enumerate(text.splitlines(), 1):
            line = raw.split('#', 1)[0].strip()
            port = re.search(r'\[get_ports (.+)\]$', line)
            if not port:
                continue
            port = port.group(1).strip().strip('{}')
            assignments = {}
            dictionary = re.search(r'-dict \{([^}]+)\}', line)
            if dictionary:
                tokens = dictionary.group(1).split()
                assignments.update(zip(tokens[::2], tokens[1::2]))
            else:
                simple = re.match(r'set_property (PACKAGE_PIN|IOSTANDARD) ([^ ]+)', line)
                if simple:
                    assignments[simple.group(1)] = simple.group(2)
            record = values.setdefault(port, {'board': board, 'port': port, 'source': relative})
            for key in ['PACKAGE_PIN', 'IOSTANDARD']:
                if key in assignments:
                    record[key.lower()] = assignments[key]
                    record['line'] = number
        rows.extend(record for record in values.values() if 'package_pin' in record)
    destination = ROOT / 'board/pinmap.csv'
    with destination.open('w', encoding='utf-8', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=['board', 'port', 'package_pin', 'iostandard', 'source', 'line'])
        writer.writeheader()
        writer.writerows(rows)
    print('Exported %d explicit pin assignments.' % len(rows))

if __name__ == '__main__':
    main()
