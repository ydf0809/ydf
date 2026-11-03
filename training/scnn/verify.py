"""Verification suite for drone SCNN parameters, numerical execution and deployment exports."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from convert_weights import (ROOT, LAYERS, audit_weight_sources, decode, export, packed_words,
                             project_path, read_embedded_rom, read_payload, read_words,
                             validate_payload)


def expect_failure(action, label):
    try:
        action()
    except (ValueError, OSError):
        return
    raise AssertionError(f"Invalid input was accepted: {label}")


def conversion_checks(payload, audit):
    generated = ROOT / "generated"
    generated.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="conversion_", dir=generated) as temp:
        temp = Path(temp)
        export(payload, temp / "weights", temp / "rom.v")
        assert decode(temp / "weights", "both")["tensors"] == payload["tensors"]
        mem_equal = [mem for _, _, mem, _, _ in LAYERS
                     if (ROOT / "weights" / mem).read_bytes() == (temp / "weights" / mem).read_bytes()]
        assert len(mem_equal) == 4, "Runtime MEM files did not roundtrip byte-for-byte"
        for name, _, _, width, _ in LAYERS:
            depth = len(packed_words(payload)[name])
            embedded = read_embedded_rom(temp / "rom.v", name, width, depth)
            final = read_embedded_rom(ROOT / "references/final_engine/drone_data_roms.v", name, width, depth)
            assert embedded == final == packed_words(payload)[name]
        expected_differences = {"conv1": 216, "conv2": 1151, "fc0": 1023, "fc1": 1024}
        assert {name: entry["coe_mem_different_values"] for name, entry in audit["layers"].items()} == expected_differences
        assert all(item["final_engine_rom_matches_mem"] for item in audit["layers"].values())
        bad = copy.deepcopy(payload)
        bad["tensors"]["fc.weight"]["values"][0] = 32768
        expect_failure(lambda: validate_payload(bad), "out-of-range signed weight")
        bad["tensors"]["fc.weight"]["values"][0] = 0.5
        expect_failure(lambda: validate_payload(bad), "fractional integer payload")
        p = temp / "weights/1/conv1_weights.mem"
        text = p.read_text()
        p.write_text(("0" if text[0] != "0" else "1") + text[1:])
        expect_failure(lambda: decode(temp / "weights", "both"), "mismatched COE/MEM")
        p.write_text("0000\n")
        expect_failure(lambda: read_words(p, 384, 9, "mem"), "truncated MEM")
        expect_failure(lambda: project_path(ROOT.parent / "outside.json"), "external project reference")
    sentinel = copy.deepcopy(payload)
    for tensor in sentinel["tensors"].values():
        tensor["values"] = [0] * len(tensor["values"])
    sentinel["tensors"]["conv1.weight"]["values"][0] = 1
    sentinel["tensors"]["conv1.weight"]["values"][(7 * 3 + 2) * 9] = -1
    sentinel["tensors"]["fc.weight"]["values"][1024] = 32767
    sentinel["tensors"]["fc.weight"]["values"][1027] = -32768
    words = packed_words(sentinel)
    assert words["conv1"][0] == 1 | (0xFFFF << (23 * 16))
    assert words["fc1"][0] == (0x7FFF << 48) | 0x8000
    return {"weights_roundtrip": 3416, "runtime_mem_files_byte_identical_after_export": len(mem_equal),
            "final_engine_rom_matches_runtime_mem": "PASS",
            "new_weight_coe_mem_differences": expected_differences,
            "rom_embedding": "PASS", "independent_lane_sentinels": "PASS", "invalid_inputs": "PASS"}


def integer_reference(spikes, payload):
    """Independent NumPy integer model with explicit padding, pooling and wrap."""
    import numpy as np
    tensors = {name: np.array(item["values"], dtype=np.int64).reshape(item["shape"])
               for name, item in payload["tensors"].items()}

    def wrap(x):
        return (x + (1 << 25)) % (1 << 26) - (1 << 25)

    def update(current, previous):
        candidate = wrap(previous + (wrap(wrap(current) - previous) // 2))
        output = candidate >= 4096
        return np.where(output, 0, candidate), output.astype(np.int64)

    def conv(x, w):
        padded = np.pad(x, ((0, 0), (1, 1), (1, 1)))
        current = np.zeros((w.shape[0], x.shape[1], x.shape[2]), dtype=np.int64)
        for row in range(3):
            for col in range(3):
                region = padded[:, row:row + x.shape[1], col:col + x.shape[2]]
                current += np.einsum("oc,chw->ohw", w[:, :, row, col], region, optimize=True)
        return current

    def pool(x):
        c, h, w = x.shape
        return x.reshape(c, h // 2, 2, w // 2, 2).max(axis=(2, 4))

    v1 = np.zeros((8, 64, 64), dtype=np.int64)
    v2 = np.zeros((16, 32, 32), dtype=np.int64)
    vf = np.zeros(2, dtype=np.int64)
    trace = []
    for step in spikes:
        v1, s1 = update(conv(step, tensors["conv1.weight"]), v1)
        v2, s2 = update(conv(pool(s1), tensors["conv2.weight"]), v2)
        vf, output = update(tensors["fc.weight"] @ pool(pool(s2)).reshape(-1), vf)
        trace.append(output)
    return np.stack(trace)


def model_checks(payload):
    import numpy as np
    import torch
    from model import HardwareSCNN, encode_pixels, hardware_random_bytes, lif
    torch.set_num_threads(4)
    model = HardwareSCNN().double()
    model.load_quantized(payload)
    pixels = read_words(ROOT / "assets/reference_frame.mem", 24, 4096, "mem")
    image = torch.tensor([[(word >> (8 * ch)) & 255 for word in pixels] for ch in range(3)],
                         dtype=torch.uint8).reshape(1, 3, 64, 64)
    results = {}
    with torch.no_grad():
        for name, data in (("reference_frame", image), ("blank_frame", torch.zeros_like(image))):
            spikes = encode_pixels(data)
            counts, trace = model.forward_spikes(spikes)
            expected = integer_reference(spikes[:, 0].numpy().astype(np.int64), payload)
            assert np.array_equal(trace[:, 0].numpy(), expected), f"Temporal spike mismatch for {name}"
            assert np.array_equal(counts[0].numpy(), expected.sum(0))
            results[name] = {"spike_counts": counts[0].to(torch.int64).tolist(), "steps_checked": 50,
                             "class_index": int(counts[0].argmax()), "integer_reference": "PASS"}
        assert results["blank_frame"]["spike_counts"] == [0, 0]
        # Signed arithmetic shift rounds negative odd values down, not toward zero.
        current_q = torch.tensor([-1, -3, 8192, -(1 << 25), (1 << 25) - 1], dtype=torch.float64)
        previous_q = torch.tensor([0, 0, 0, (1 << 25) - 1, -(1 << 25)], dtype=torch.float64)
        def signed(x):
            return (x + (1 << 25)) % (1 << 26) - (1 << 25)
        candidates = [signed(int(v) + (signed(int(i) - int(v)) >> 1)) for i, v in zip(current_q, previous_q)]
        v, s = lif(current_q / 4096, previous_q / 4096)
        assert s.tolist() == [float(c >= 4096) for c in candidates]
        assert (v * 4096).tolist() == [0.0 if c >= 4096 else float(c) for c in candidates]
    # Known register timing: first byte is reset output, second is the seed MSB.
    random_bytes = hardware_random_bytes(1)
    assert random_bytes[:, :, 0, 0].tolist() == [[0, 0, 0]]
    assert random_bytes[0, :, 0, 1].tolist() == [188, 141, 157]
    return {"model_parameter_count": sum(p.numel() for p in model.parameters()),
            "signed_lif_edges": "PASS", "encoder_reset_alignment": "PASS", **results}


def relocation_check():
    generated = ROOT / "generated"
    with tempfile.TemporaryDirectory(prefix="moved_", dir=generated) as temp:
        moved = Path(temp) / "project"
        shutil.copytree(ROOT, moved, ignore=shutil.ignore_patterns("generated", "__pycache__"))
        commands = [[sys.executable, "-B", str(moved / "convert_weights.py"), "decode", "--format", "mem"],
                    [sys.executable, "-B", str(moved / "convert_weights.py"), "encode"]]
        # A different cwd catches accidental reliance on the original working directory.
        for command in commands:
            result = subprocess.run(command, cwd=temp, capture_output=True, text=True)
            if result.returncode:
                raise AssertionError(result.stdout + result.stderr)
        assert read_payload(moved / "parameters/final_engine_weights.json")["tensors"] == decode(ROOT / "weights", "mem")["tensors"]
        assert read_payload(moved / "parameters/new_weight_coe_weights.json")["tensors"] == decode(ROOT / "references/new_weight_coe", "coe")["tensors"]
    return "PASS"


def main():
    manifest = json.loads((ROOT / "source_manifest.json").read_text(encoding="utf-8"))
    for rel, digest in manifest["files"].items():
        assert hashlib.sha256(project_path(rel).read_bytes()).hexdigest() == digest, f"Source changed: {rel}"
    payload = read_payload(ROOT / "parameters/final_engine_weights.json")
    assert payload["tensors"] == decode(ROOT / "weights", "mem")["tensors"]
    coe_payload = read_payload(ROOT / "parameters/new_weight_coe_weights.json")
    assert coe_payload["tensors"] == decode(ROOT / "references/new_weight_coe", "coe")["tensors"]
    assert payload["tensors"] == decode(ROOT / "weights", "both")["tensors"]
    audit = audit_weight_sources(ROOT / "weights", ROOT / "references/final_engine/drone_data_roms.v",
                                 ROOT / "references/new_weight_coe")
    manifest_differences = {name: record["coe_mem_different_values"]
                            for name, record in manifest["weight_source_audit"]["layers"].items()}
    actual_differences = {name: record["coe_mem_different_values"] for name, record in audit["layers"].items()}
    assert actual_differences == manifest_differences
    report = {"status": "PASS", "source_sha256": "PASS",
              "parameter_authority": "final-engine ROM values; byte-exact MEM source",
              "canonical_coe_mem_agreement": "PASS",
              "weight_source_audit": audit,
              "conversion": conversion_checks(payload, audit)}
    (ROOT / "generated/weight_source_audit.json").write_text(json.dumps(audit, indent=2) + "\n", encoding="utf-8")
    print("Final-engine MEM/ROM parameters and new COE provenance: PASS", flush=True)
    report["functional_model"] = {
        "final_engine_parameters": model_checks(payload),
        "new_weight_coe_parameters": model_checks(coe_payload),
    }
    print("Both parameter sets match the independent 50-step integer reference: PASS", flush=True)
    report["relocation"] = relocation_check()
    report["real_dataset_training"] = "NOT RUN: no dataset supplied"
    report["rtl_simulation_and_bitstream"] = "NOT RUN: existing FPGA project is not modified"
    output = ROOT / "generated/verification.json"
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
