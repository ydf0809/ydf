"""Training and fine-tuning of the drone recognition SCNN with quantization-aware forward arithmetic."""
from __future__ import annotations

import argparse
import hashlib
import json
import random

import numpy as np
from PIL import Image
import torch
from torch.nn import functional as F
from torch.utils.data import DataLoader, Dataset

from convert_weights import ROOT, SCALE, project_path, read_payload
from model import HardwareSCNN

CLASSES = ("not_drone", "drone")
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff", ".webp"}


class RoiDataset(Dataset):
    def __init__(self, root):
        if not root.is_dir() or {p.name for p in root.iterdir() if p.is_dir()} != set(CLASSES):
            raise ValueError(f"{root.relative_to(ROOT)} must contain exactly not_drone/ and drone/")
        self.samples = []
        for label, name in enumerate(CLASSES):
            paths = sorted(p for p in (root / name).rglob("*") if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES)
            if not paths:
                raise ValueError(f"No images for {root.relative_to(ROOT)}/{name}")
            self.samples.extend((project_path(path), label) for path in paths)

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, index):
        path, label = self.samples[index]
        with Image.open(path) as image:
            if image.size != (64, 64):
                raise ValueError(f"{path.relative_to(ROOT)} must already be a preprocessed 64x64 ROI")
            rgb = np.array(image.convert("RGB"), dtype=np.uint8)
        bgr = rgb.transpose(2, 0, 1)[[2, 1, 0]].copy()
        return torch.from_numpy(bgr), label


def checkpoint(model, args, epoch, accuracy):
    weight_path = project_path(args.weights)
    source = {
        "kind": "random_initialization" if args.from_scratch else "pretrained_parameters",
        "file": None if args.from_scratch else weight_path.relative_to(ROOT).as_posix(),
        "sha256": None if args.from_scratch else hashlib.sha256(weight_path.read_bytes()).hexdigest(),
    }
    return {
        "schema": "scnn-training-v1",
        "model_spec": json.loads((ROOT / "model_spec.json").read_text(encoding="utf-8")),
        "model_state": {name: value.detach().cpu() for name, value in model.state_dict().items()},
        "bundled_source_sha256": json.loads((ROOT / "source_manifest.json").read_text(encoding="utf-8"))["files"],
        "parameter_source": source,
        "training": {"method": "surrogate-gradient quantization-aware training", "optimizer": "Adam",
                     "loss": "cross_entropy_of_output_spike_counts", "reset_gradient": "detached hard reset",
                     "surrogate": "fast_sigmoid_slope_5", "seed": args.seed,
                     "epochs": args.epochs, "batch_size": args.batch_size, "learning_rate": args.lr,
                     "from_scratch": args.from_scratch, "time_steps": 50},
        "epoch": epoch, "validation_accuracy": accuracy,
    }


def smoke_test(model, args):
    """Synthetic data validates code execution only; it is not training evidence."""
    from convert_weights import export
    from model import encode_pixels
    pixels = torch.randint(0, 256, (2, 3, 64, 64), dtype=torch.uint8)
    before = {name: parameter.detach().clone() for name, parameter in model.named_parameters()}
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)
    counts, _ = model.forward_spikes(encode_pixels(pixels, steps=3))
    loss = F.cross_entropy(counts, torch.tensor([0, 1]))
    loss.backward()
    for name, parameter in model.named_parameters():
        if parameter.grad is None or not torch.isfinite(parameter.grad).all() or not parameter.grad.abs().any():
            raise AssertionError(f"No finite nonzero gradient for {name}")
    optimizer.step()
    with torch.no_grad():
        for parameter in model.parameters():
            parameter.clamp_(-32768 / SCALE, 32767 / SCALE)
    changed = [name for name, parameter in model.named_parameters() if not torch.equal(before[name], parameter)]
    if len(changed) != 3:
        raise AssertionError(f"Optimizer did not update all three tensors: {changed}")
    output = project_path("generated/smoke_checkpoint.pt")
    output.parent.mkdir(parents=True, exist_ok=True)
    saved = checkpoint(model, args, 0, None)
    saved["training"]["smoke_only"] = True
    saved["training"]["time_steps"] = 3
    saved["training"]["learning_rate"] = 1e-3
    torch.save(saved, output)
    export(read_payload(output), project_path("generated/smoke_weights"))
    report = {"smoke_test": "PASS", "synthetic_samples": 2, "time_steps": 3,
              "loss": loss.item(), "updated_tensors": changed,
              "checkpoint_export": "PASS", "real_dataset_training": False}
    (ROOT / "generated/smoke_test.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", default="data")
    parser.add_argument("--weights", default="parameters/final_engine_weights.json",
                        help="Select parameters from the final engine or the separate new weight COE reference")
    parser.add_argument("--output", default="generated/training")
    parser.add_argument("--epochs", type=int, help="Number of epochs; required for dataset training")
    parser.add_argument("--batch-size", type=int, help="Batch size; required for dataset training")
    parser.add_argument("--lr", type=float, help="Learning rate; required for dataset training")
    parser.add_argument("--seed", type=int, default=0, help="Random seed for reproducible experiment execution")
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--from-scratch", action="store_true", help="Explicitly choose new random initialization")
    parser.add_argument("--smoke-test", action="store_true")
    args = parser.parse_args()
    torch.set_num_threads(4)
    random.seed(args.seed); np.random.seed(args.seed); torch.manual_seed(args.seed)
    model = HardwareSCNN().double()
    if not args.from_scratch:
        path = project_path(args.weights)
        model.load_quantized(read_payload(path))
    if args.smoke_test:
        smoke_test(model, args)
        return
    if args.epochs is None or args.batch_size is None or args.lr is None:
        parser.error("Dataset training requires explicit --epochs, --batch-size and --lr settings")
    if args.epochs <= 0 or args.batch_size <= 0 or not np.isfinite(args.lr) or args.lr <= 0:
        parser.error("Epochs, batch size and learning rate must be positive and finite")
    data = project_path(args.data)
    train_data, val_data = RoiDataset(data / "train"), RoiDataset(data / "val")
    output = project_path(args.output)
    if not output.is_relative_to(ROOT / "generated"):
        parser.error("Training output must stay inside generated/")
    output.mkdir(parents=True, exist_ok=True)
    manifest = {split: [{"path": path.relative_to(ROOT).as_posix(), "label": label,
                         "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                        for path, label in dataset.samples]
                for split, dataset in (("train", train_data), ("val", val_data))}
    if {s["sha256"] for s in manifest["train"]} & {s["sha256"] for s in manifest["val"]}:
        parser.error("Training and validation contain identical image files; split them without leakage")
    (output / "data_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    train_loader = DataLoader(train_data, batch_size=args.batch_size, shuffle=True, num_workers=0)
    val_loader = DataLoader(val_data, batch_size=args.batch_size, shuffle=False, num_workers=0)
    model.to(args.device)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
    history, best = [], -1.0
    for epoch in range(1, args.epochs + 1):
        model.train()
        total_loss, correct = 0.0, 0
        for pixels, labels in train_loader:
            pixels, labels = pixels.to(args.device), labels.to(args.device)
            optimizer.zero_grad()
            counts, _ = model(pixels)
            loss = F.cross_entropy(counts, labels)
            if not torch.isfinite(loss):
                raise RuntimeError("Nonfinite training loss; no checkpoint exported")
            loss.backward(); optimizer.step()
            with torch.no_grad():
                for parameter in model.parameters():
                    parameter.clamp_(-32768 / SCALE, 32767 / SCALE)
            total_loss += loss.item() * len(labels)
            correct += (counts.argmax(1) == labels).sum().item()
        model.eval()
        val_correct = 0
        with torch.no_grad():
            for pixels, labels in val_loader:
                counts, _ = model(pixels.to(args.device))
                val_correct += (counts.argmax(1).cpu() == labels).sum().item()
        accuracy = val_correct / len(val_data)
        row = {"epoch": epoch, "loss": total_loss / len(train_data),
               "train_accuracy": correct / len(train_data), "val_accuracy": accuracy}
        history.append(row); print(json.dumps(row), flush=True)
        saved = checkpoint(model, args, epoch, accuracy)
        torch.save(saved, output / "latest.pt")
        if accuracy > best:
            best = accuracy; torch.save(saved, output / "best.pt")
        (output / "history.json").write_text(json.dumps(history, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
