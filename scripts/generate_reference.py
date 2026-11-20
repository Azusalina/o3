"""Generate a deterministic PyTorch reference for the simulator Core ML parity test."""
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[1]
weights = Path(sys.argv[1])
assert hashlib.sha256(weights.read_bytes()).hexdigest() == "e05e460e02fbeb745ab2984edf4f4898c5035f6a475183be4ee16f52226b45b1"
torch.set_num_threads(2)
model = torch.jit.load(str(weights), map_location="cpu").float().eval()
# Integer modulo is shared exactly with the Swift parity test.
image = ((np.arange(3 * 256 * 256, dtype=np.int32) * 37 % 251).astype(np.float32) / 1000).reshape(1, 3, 256, 256)
with torch.no_grad():
    result = model(torch.from_numpy(image), torch.tensor([[1.0]])).numpy()
assert np.isfinite(result).all() and result.min() >= 0 and result.max() <= 1
assert np.mean(np.abs(result - image)) > 0.001, "Denoiser unexpectedly acts as identity"
destination = ROOT / "Tests/Fixtures"
destination.mkdir(exist_ok=True)
result.astype("<f4").tofile(destination / "rawforge-reference.f32")
stats = {"input": "((index * 37) % 251) / 1000", "iso": 6400,
         "shape": list(result.shape), "min": float(result.min()), "max": float(result.max()),
         "mean_absolute_change": float(np.mean(np.abs(result - image))),
         "weights_sha256": hashlib.sha256(weights.read_bytes()).hexdigest()}
(destination / "reference.json").write_text(json.dumps(stats, indent=2) + "\n")
print(json.dumps(stats, indent=2))
