"""FPGA-compatible spiking convolutional network for drone target recognition.

The network uses Q12 forward arithmetic and surrogate-gradient optimization.
Float64 represents integer-derived forward calculations exactly. Each call
initializes membrane potentials and the input encoder to their reset states.
"""
from __future__ import annotations

from functools import lru_cache

import torch
from torch import nn
from torch.nn import functional as F

from convert_weights import SCALE, validate_payload


def wrap26(x: torch.Tensor) -> torch.Tensor:
    return torch.remainder(x + (1 << 25), 1 << 26) - (1 << 25)


class SurrogateSpike(torch.autograd.Function):
    @staticmethod
    def forward(ctx, distance):
        ctx.save_for_backward(distance)
        return (distance >= 0).to(distance.dtype)

    @staticmethod
    def backward(ctx, grad):
        (distance,) = ctx.saved_tensors
        # Fast-sigmoid surrogate derivative with slope parameter 5.
        return grad / (1 + 5 * distance.abs()).square()


def quantized_weight(weight: torch.Tensor) -> torch.Tensor:
    q = torch.round(weight * SCALE).clamp(-32768, 32767) / SCALE
    return weight + (q - weight).detach()


def lif(current: torch.Tensor, previous: torch.Tensor | float):
    current_q = wrap26(torch.round(current * SCALE))
    previous_q = torch.round(previous * SCALE) if isinstance(previous, torch.Tensor) else 0
    diff_q = wrap26(current_q - previous_q)
    candidate_q = wrap26(previous_q + torch.floor(diff_q / 2))
    smooth = previous + (current - previous) / 2
    candidate = smooth + (candidate_q / SCALE - smooth).detach()
    spike = SurrogateSpike.apply(candidate - 1.0)
    return candidate * (1 - spike.detach()), spike


@lru_cache(maxsize=4)
def hardware_random_bytes(steps: int) -> torch.Tensor:
    """Captured bytes for one 64x64 frame sequence after global RTL reset.

    input_frontend samples the previous registered PRNG output at S_CAP,
    so the first captured byte is reset value 0, followed by LFSR outputs.
    The random stream continues across time steps (not reseeded each step).
    """
    if not 1 <= steps <= 50:
        raise ValueError("Time steps must be in 1..50")
    streams = []
    for instance in (1, 2, 3):
        state = (0xACE1F00D ^ ((instance * 0x10101011) & 0xFFFFFFFF)
                 ^ (instance << 7) ^ (instance << 15) ^ (instance << 23)) & 0xFFFFFFFF
        output = 0
        stream = []
        for _ in range(steps * 4096):
            stream.append(output)
            output = state >> 24
            feedback = ((state >> 0) ^ (state >> 1) ^ (state >> 21) ^ (state >> 31)) & 1
            state = ((state << 1) & 0xFFFFFFFF) | feedback
        streams.append(torch.tensor(stream, dtype=torch.uint8).reshape(steps, 64, 64))
    return torch.stack(streams, dim=1)


def encode_pixels(pixels: torch.Tensor, steps: int = 50) -> torch.Tensor:
    """BGR uint8 [batch,3,64,64] -> binary [steps,batch,3,64,64]."""
    if pixels.dtype != torch.uint8 or pixels.ndim != 4 or tuple(pixels.shape[1:]) != (3, 64, 64):
        raise ValueError("Expected uint8 BGR pixels [batch,3,64,64]")
    random_bytes = hardware_random_bytes(steps).to(pixels.device)
    return (random_bytes[:, None] < pixels[None]).to(torch.float64)


class HardwareSCNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv2d(3, 8, 3, padding=1, bias=False)
        self.conv2 = nn.Conv2d(8, 16, 3, padding=1, bias=False)
        self.fc = nn.Linear(1024, 2, bias=False)

    def load_quantized(self, payload: dict) -> None:
        validate_payload(payload)
        state = {name: torch.tensor(item["values"], dtype=torch.float64).reshape(item["shape"]) / SCALE
                 for name, item in payload["tensors"].items()}
        self.load_state_dict(state, strict=True)

    def forward(self, pixels: torch.Tensor, steps: int = 50):
        return self.forward_spikes(encode_pixels(pixels, steps))

    def forward_spikes(self, spikes: torch.Tensor):
        if spikes.ndim != 5 or tuple(spikes.shape[2:]) != (3, 64, 64) or not 1 <= len(spikes) <= 50:
            raise ValueError("Expected binary spikes [steps<=50,batch,3,64,64]")
        if not torch.all((spikes == 0) | (spikes == 1)):
            raise ValueError("Input spikes must be binary")
        w1, w2, wf = (quantized_weight(layer.weight) for layer in (self.conv1, self.conv2, self.fc))
        v1 = v2 = vf = 0.0
        counts = torch.zeros((spikes.shape[1], 2), device=spikes.device, dtype=w1.dtype)
        trace = []
        for step in spikes:
            v1, s1 = lif(F.conv2d(step.to(w1.dtype), w1, padding=1), v1)
            p1 = F.max_pool2d(s1, 2)
            v2, s2 = lif(F.conv2d(p1, w2, padding=1), v2)
            p3 = F.max_pool2d(F.max_pool2d(s2, 2), 2)
            vf, output = lif(F.linear(p3.flatten(1), wf), vf)
            counts = counts + output
            trace.append(output)
        return counts, torch.stack(trace)
