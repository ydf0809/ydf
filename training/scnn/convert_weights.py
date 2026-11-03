"""Parameter import and FPGA deployment export for the drone recognition SCNN.

The training checkpoint path imports torch lazily. JSON conversion needs no torch.
Tensor layout is OIHW for convolutions and OI for the classifier.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
SCALE = 4096
SHAPES = {"conv1.weight": [8, 3, 3, 3], "conv2.weight": [16, 8, 3, 3], "fc.weight": [2, 1024]}
LAYERS = (
    ("conv1", "0/conv1_weights.coe", "1/conv1_weights.mem", 384, 9),
    ("conv2", "2/conv2_weights.coe", "3/conv2_weights.mem", 2048, 9),
    ("fc0", "4/fc_weights_0.coe", "5/fc_weights_0.mem", 64, 256),
    ("fc1", "6/fc_weights_1.coe", "7/fc_weights_1.mem", 64, 256),
)


def project_path(path: str | Path) -> Path:
    path = Path(path)
    result = (path if path.is_absolute() else ROOT / path).resolve()
    if not result.is_relative_to(ROOT):
        raise ValueError("Path must stay inside this script project; copy required inputs into it first")
    return result


def write_file(path: Path, data: bytes) -> None:
    path = project_path(path)
    if path.is_relative_to(ROOT / "weights") or path.is_relative_to(ROOT / "assets"):
        raise ValueError("Bundled source weights and reference assets are read-only inputs")
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or path.read_bytes() != data:
        path.write_bytes(data)


def write_json(path: Path, data: dict) -> None:
    write_file(path, (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))


def read_words(path: Path, width: int, depth: int, kind: str) -> list[int]:
    text = path.read_text(encoding="ascii")
    if kind == "coe":
        match = re.fullmatch(
            r"\s*memory_initialization_radix\s*=\s*16\s*;\s*"
            r"memory_initialization_vector\s*=\s*(.*?)\s*;\s*", text, re.I | re.S,
        )
        if not match:
            raise ValueError(f"{path.name}: expected radix-16 COE header and terminating semicolon")
        tokens = [token.strip() for token in match[1].split(",")]
        # A COE can store the same lanes as 64-bit entries or as wide ROM words.
        if any(not token or len(token) % 4 or not re.fullmatch(r"[0-9a-fA-F]+", token) for token in tokens):
            raise ValueError(f"{path.name}: malformed hexadecimal COE data")
        data = "".join(tokens)
        chars = width // 4
        if len(data) != depth * chars:
            raise ValueError(f"{path.name}: expected {depth * chars} hex digits, got {len(data)}")
        words = [int(data[i:i + chars], 16) for i in range(0, len(data), chars)]
    else:
        tokens = text.split()
        if any(len(token) != width // 4 or not re.fullmatch(r"[0-9a-fA-F]+", token) for token in tokens):
            raise ValueError(f"{path.name}: invalid {width}-bit MEM word")
        words = [int(token, 16) for token in tokens]
    if len(words) != depth:
        raise ValueError(f"{path.name}: expected {depth} ROM words, got {len(words)}")
    return words


def signed16(value: int) -> int:
    value &= 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


def unpack_parameter_values(words: list[int], width: int) -> list[int]:
    return [signed16(word >> (16 * lane)) for word in words for lane in range(width // 16)]


def decode(source: Path, kind: str = "both") -> dict:
    words = {}
    hashes = {}
    for name, coe, mem, width, depth in LAYERS:
        variants = {}
        for fmt, rel in (("coe", coe), ("mem", mem)):
            if kind in (fmt, "both"):
                path = source / rel
                variants[fmt] = read_words(path, width, depth, fmt)
                hashes[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
        if kind == "both" and variants["coe"] != variants["mem"]:
            raise ValueError(f"{name}: COE/MEM contain different weights; choose a verified source explicitly")
        words[name] = next(iter(variants.values()))
    tensors = {}
    for name, cin, cout in (("conv1", 3, 8), ("conv2", 8, 16)):
        # The low lane is ci=0, co=0. Torch flatten order is co, ci, kr, kc.
        values = [signed16(words[name][tap] >> (16 * (ci * cout + co)))
                  for co in range(cout) for ci in range(cin) for tap in range(9)]
        tensors[name + ".weight"] = {"shape": SHAPES[name + ".weight"], "values": values}
    fc = [signed16(words[f"fc{out}"][index // 4] >> (16 * (3 - index % 4)))
          for out in range(2) for index in range(1024)]
    tensors["fc.weight"] = {"shape": SHAPES["fc.weight"], "values": fc}
    result = {"schema": "scnn-q12-v1", "fraction_bits": 12, "class_names": ["not_drone", "drone"],
              "input_channel_order": ["B", "G", "R"], "source_sha256": hashes, "tensors": tensors}
    validate_payload(result)
    return result


def read_embedded_rom(path: Path, name: str, width: int, depth: int) -> list[int]:
    text = path.read_text(encoding="ascii")
    match = re.search(r"module\s+drone_" + re.escape(name) + r"_rom\b(.*?)endmodule", text, re.S)
    if not match:
        raise ValueError(f"{path}: missing drone_{name}_rom module")
    words = [None] * depth
    for address_text, width_text, value_text in re.findall(
        r"mem\[\s*(\d+)\s*\]\s*=\s*(\d+)'h([0-9a-fA-F]+)", match[1]
    ):
        address, declared_width, value = int(address_text), int(width_text), int(value_text, 16)
        if declared_width != width or address >= depth or words[address] is not None:
            raise ValueError(f"{path}: invalid or duplicate drone_{name}_rom entry at {address}")
        words[address] = value
    if any(word is None for word in words):
        raise ValueError(f"{path}: drone_{name}_rom has missing ROM entries")
    return words


def audit_weight_sources(source: Path, rom: Path, coe_source: Path | None = None) -> dict:
    coe_source = coe_source or source
    layers = {}
    for name, coe, mem, width, depth in LAYERS:
        coe_path, mem_path = coe_source / coe, source / mem
        coe_words = read_words(coe_path, width, depth, "coe")
        mem_words = read_words(mem_path, width, depth, "mem")
        rom_words = read_embedded_rom(rom, name, width, depth)
        coe_values = unpack_parameter_values(coe_words, width)
        mem_values = unpack_parameter_values(mem_words, width)
        differences = [{"index": index, "coe": coe_values[index], "mem": mem_values[index]}
                       for index in range(len(coe_values)) if coe_values[index] != mem_values[index]]
        if mem_words != rom_words:
            raise ValueError(f"{name}: final-engine ROM does not match packaged MEM values")
        layers[name] = {
            "parameter_count": len(mem_values),
            "coe_sha256": hashlib.sha256(coe_path.read_bytes()).hexdigest(),
            "mem_sha256": hashlib.sha256(mem_path.read_bytes()).hexdigest(),
            "coe_values_match_mem": not differences,
            "coe_mem_different_values": len(differences),
            "first_differences": differences[:8],
            "final_engine_rom_matches_mem": True,
            "rom_words": len(rom_words),
        }
    return {
        "schema": "scnn-weight-source-audit-v1",
        "training_initialization": "MEM values verified against final-engine drone_data_roms.v",
        "coe_role": ("canonical deployment COE" if coe_source.resolve() == source.resolve()
                     else "historical alternative COE reference; not active deployment weights"),
        "final_engine_rom_sha256": hashlib.sha256(rom.read_bytes()).hexdigest(),
        "layers": layers,
    }


def validate_payload(payload: dict) -> None:
    if payload.get("schema") != "scnn-q12-v1" or payload.get("fraction_bits") != 12:
        raise ValueError("Expected scnn-q12-v1 with 12 fractional bits")
    if payload.get("class_names") != ["not_drone", "drone"] or payload.get("input_channel_order") != ["B", "G", "R"]:
        raise ValueError("Class indices or input channel order do not match this RTL")
    if set(payload.get("tensors", {})) != set(SHAPES):
        raise ValueError("Expected exactly conv1.weight, conv2.weight and fc.weight")
    for name, shape in SHAPES.items():
        tensor = payload["tensors"][name]
        values = tensor.get("values", [])
        if tensor.get("shape") != shape or len(values) != math.prod(shape):
            raise ValueError(f"{name}: shape/length mismatch")
        if any(type(v) is not int or not -32768 <= v <= 32767 for v in values):
            raise ValueError(f"{name}: values must be signed 16-bit integers")


def read_payload(path: Path) -> dict:
    if path.suffix.lower() == ".json":
        payload = json.loads(path.read_text(encoding="utf-8"))
    else:
        import torch
        checkpoint = torch.load(path, map_location="cpu", weights_only=True)
        if checkpoint.get("schema") != "scnn-training-v1":
            raise ValueError("Only checkpoints produced by this train.py are supported")
        expected_spec = json.loads((ROOT / "model_spec.json").read_text(encoding="utf-8"))
        checkpoint_spec = checkpoint.get("model_spec")
        if not isinstance(checkpoint_spec, dict) or any(checkpoint_spec.get(key) != value for key, value in expected_spec.items()):
            raise ValueError("Checkpoint model specification does not match this project")
        payload = {"schema": "scnn-q12-v1", "fraction_bits": 12, "class_names": ["not_drone", "drone"],
                   "input_channel_order": ["B", "G", "R"], "tensors": {}}
        state = checkpoint["model_state"]
        if set(state) != set(SHAPES):
            raise ValueError("Unexpected checkpoint parameters; biases/extra layers are not supported")
        for name, shape in SHAPES.items():
            tensor = state[name].detach().cpu().double()
            if list(tensor.shape) != shape or not torch.isfinite(tensor).all():
                raise ValueError(f"{name}: invalid tensor shape or nonfinite value")
            q = torch.round(tensor * SCALE)
            if (q < -32768).any() or (q > 32767).any():
                raise ValueError(f"{name}: weight outside Q12 signed-16 range; export does not silently clip")
            payload["tensors"][name] = {"shape": shape, "values": q.to(torch.int64).flatten().tolist()}
    validate_payload(payload)
    return payload


def packed_words(payload: dict) -> dict[str, list[int]]:
    validate_payload(payload)
    words = {}
    for name, cin, cout in (("conv1", 3, 8), ("conv2", 8, 16)):
        values = payload["tensors"][name + ".weight"]["values"]
        words[name] = [sum((values[(co * cin + ci) * 9 + tap] & 0xFFFF) << (16 * (ci * cout + co))
                           for ci in range(cin) for co in range(cout)) for tap in range(9)]
    values = payload["tensors"]["fc.weight"]["values"]
    for out in range(2):
        words[f"fc{out}"] = [sum((values[out * 1024 + addr * 4 + lane] & 0xFFFF) << (16 * (3 - lane))
                                 for lane in range(4)) for addr in range(256)]
    return words


def export(payload: dict, destination: Path, rom: Path | None = None, frame: Path | None = None) -> None:
    words = packed_words(payload)
    for name, coe, mem, width, _ in LAYERS:
        lines = [f"{word:0{width // 4}X}" for word in words[name]]
        mem_data = ("\r\n".join(lines) + "\r\n").encode("ascii")
        coe_lines = ["memory_initialization_radix=16;", "memory_initialization_vector="]
        coe_lines += [value + (";" if i == len(lines) - 1 else ",") for i, value in enumerate(lines)]
        coe_data = ("\r\n".join(coe_lines) + "\r\n").encode("ascii")
        write_file(destination / mem, mem_data)
        write_file(destination / coe, coe_data)
    write_json(destination / "export_manifest.json", {
        "schema": "scnn-q12-export-v1", "weights": 3416,
        "parameter_source_sha256": payload.get("source_sha256", {}),
        "sha256": {rel: hashlib.sha256((destination / rel).read_bytes()).hexdigest()
                   for _, coe, mem, _, _ in LAYERS for rel in (coe, mem)},
    })
    if rom is not None:
        frame = frame or ROOT / "assets/reference_frame.mem"
        pixels = read_words(frame, 24, 4096, "mem")
        write_file(rom, emit_roms(words, pixels).encode("ascii"))


def emit_roms(words: dict[str, list[int]], pixels: list[int]) -> str:
    parts = ["// Generated by convert_weights.py; all data is embedded.\n`timescale 1ns / 1ps"]
    for name, _, _, width, depth in LAYERS:
        assignments = "\n".join(f"        mem[{i}] = {width}'h{word:0{width // 4}X};" for i, word in enumerate(words[name]))
        if name.startswith("conv"):
            parts.append(f"""module drone_{name}_rom #(parameter P_DATA_WIDTH={width}, parameter P_DEPTH={depth}) (
    input wire [$clog2(P_DEPTH)-1:0] i_tap_addr,
    output wire [P_DATA_WIDTH-1:0] o_word);
    (* rom_style = "block" *) reg [P_DATA_WIDTH-1:0] mem [0:P_DEPTH-1];
    initial begin
{assignments}
    end
    assign o_word=mem[i_tap_addr];
endmodule""")
        else:
            parts.append(f"""module drone_{name}_rom (input wire clka, input wire ena,
    input wire [7:0] addra, output wire [63:0] douta);
    (* rom_style = "block" *) reg [63:0] mem [0:255];
    reg [63:0] rd1, rd2;
    initial begin
{assignments}
    end
    always @(posedge clka) begin rd1<=mem[addra]; rd2<=rd1; end
    assign douta=rd2;
endmodule""")
    assignments = "\n".join(f"        mem[{i}]=24'h{word:06X};" for i, word in enumerate(pixels))
    parts.append(f"""module drone_frame_rom (input wire [11:0] addr, output wire [23:0] data);
    (* rom_style = "block" *) reg [23:0] mem [0:4095];
    initial begin
{assignments}
    end
    assign data=mem[addr];
endmodule""")
    return "\n\n".join(parts) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    dec = sub.add_parser("decode", help="COE/MEM -> signed Q12 tensor JSON")
    dec.add_argument("--source", default="weights")
    dec.add_argument("--format", choices=("both", "coe", "mem"), default="mem",
                     help="Training initialization defaults to final-engine MEM parameters")
    dec.add_argument("--output", default="parameters/final_engine_weights.json")
    audit = sub.add_parser("audit", help="Compare COE, MEM and embedded final-engine ROM values")
    audit.add_argument("--source", default="weights")
    audit.add_argument("--coe-source", default="weights")
    audit.add_argument("--rom", default="references/final_engine/drone_data_roms.v")
    audit.add_argument("--output", default="generated/weight_source_audit.json")
    enc = sub.add_parser("encode", help="Tensor JSON or train.py checkpoint -> COE/MEM and optional embedded RTL")
    enc.add_argument("--input", default="parameters/final_engine_weights.json")
    enc.add_argument("--output", default="generated/final_engine_weights")
    enc.add_argument("--rom", help="Optional generated Verilog output path")
    enc.add_argument("--frame", default="assets/reference_frame.mem")
    args = parser.parse_args()
    try:
        if args.command == "decode":
            payload = decode(project_path(args.source), args.format)
            write_json(project_path(args.output), payload)
            print(f"Decoded 3416 signed Q12 weights from {args.format.upper()} -> {project_path(args.output).relative_to(ROOT)}")
        elif args.command == "audit":
            report = audit_weight_sources(project_path(args.source), project_path(args.rom),
                                          project_path(args.coe_source))
            write_json(project_path(args.output), report)
            print(f"Audited COE/MEM/final-engine ROM -> {project_path(args.output).relative_to(ROOT)}")
        else:
            export(read_payload(project_path(args.input)), project_path(args.output),
                   project_path(args.rom) if args.rom else None, project_path(args.frame))
            print(f"Exported four COE/MEM pairs -> {project_path(args.output).relative_to(ROOT)}")
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        parser.exit(2, f"ERROR: {error}\n")


if __name__ == "__main__":
    main()
