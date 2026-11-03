"""Shared paths and tool invocation for the two board projects."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BOARDS = {
    'upper': {
        'directory': 'projects/merged_cam_lcd_voice_scnn',
        'xpr': 'merged_cam_lcd_voice_scnn.xpr',
        'rtl': 'rtl', 'tests': 'merged_cam_lcd_voice_scnn.srcs/sim_1/new',
        'top': 'top', 'system_verilog': True,
    },
    'lower': {
        'directory': 'projects/realfinal_min_102404',
        'xpr': 'realfinal.xpr',
        'rtl': 'realfinal.srcs/sources_1',
        'tests': 'realfinal.srcs/sim_1/new',
        'top': 'super_top', 'system_verilog': True,
    },
}
INPUT_SUFFIXES = {'.v', '.sv', '.vh', '.svh', '.vhd', '.xdc', '.xci',
                  '.coe', '.mem', '.hex', '.mif', '.dat'}

def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def input_hashes(board):
    folder = ROOT / BOARDS[board]['directory']
    return {p.relative_to(ROOT).as_posix(): sha256(p)
            for p in sorted(folder.rglob('*'))
            if p.is_file() and p.suffix.lower() in INPUT_SUFFIXES
            and not any(part.endswith(('.runs', '.gen', '.cache', '.sim'))
                        for part in p.relative_to(folder).parts)}

def tool_bin(value=None):
    if value:
        result = Path(value).resolve()
    elif os.environ.get('XILINX_VIVADO'):
        result = Path(os.environ['XILINX_VIVADO']) / 'bin'
    else:
        executable = shutil.which('vivado.bat') or shutil.which('vivado')
        if not executable:
            raise RuntimeError('Provide --vivado-bin or set XILINX_VIVADO.')
        result = Path(executable).parent
    return result

def environment():
    result = os.environ.copy()
    if os.name == 'nt' and not result.get('PROCESSOR_ARCHITECTURE'):
        result['PROCESSOR_ARCHITECTURE'] = 'AMD64'
    return result

def command(bin_dir, name, arguments):
    suffix = '.bat' if os.name == 'nt' else ''
    executable = Path(bin_dir) / (name + suffix)
    if not executable.is_file():
        raise FileNotFoundError(executable)
    return [str(executable), *map(str, arguments)]

def public_text(text):
    replacements = [(str(ROOT), '[repository]'),
                    (ROOT.as_posix(), '[repository]')]
    profile = os.environ.get('USERPROFILE')
    if profile:
        replacements += [(profile, '[user]'),
                         (profile.replace(chr(92), '/'), '[user]')]
    for before, after in sorted(replacements, key=lambda x: -len(x[0])):
        text = text.replace(before, after)
    return text

def execute(bin_dir, name, arguments, cwd, timeout):
    arguments = command(bin_dir, name, arguments)
    with subprocess.Popen(arguments, cwd=cwd, env=environment(),
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          encoding='utf-8', errors='replace') as process:
        try:
            text, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            process.kill()
            text, _ = process.communicate()
            raise subprocess.TimeoutExpired(arguments, timeout, output=text)
        return process.returncode, text

def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=True, indent=2) + '\n',
                    encoding='utf-8')
