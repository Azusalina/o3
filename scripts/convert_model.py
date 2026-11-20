"""Convert RawForge's signed TorchScript Super Light model to an iOS 18 ML Program."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

import coremltools as ct
import numpy as np
import torch

URL = "https://github.com/rymuelle/RawRefinery/releases/download/v1.2.1-alpha/ShadowWeightedL1_super_light.pt"
SHA256 = "e05e460e02fbeb745ab2984edf4f4898c5035f6a475183be4ee16f52226b45b1"
ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--weights", type=Path, default=ROOT / ".model-cache/model.pt")
    parser.add_argument("--verify", action="store_true", help="Compare Core ML with Torch; requires macOS")
    args = parser.parse_args()
    if not args.weights.exists():
        args.weights.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(URL, args.weights)
    if hashlib.sha256(args.weights.read_bytes()).hexdigest() != SHA256:
        raise RuntimeError("Upstream model checksum mismatch")
    torch.set_num_threads(2)
    model = torch.jit.load(str(args.weights), map_location="cpu").float().eval()
    converted = ct.convert(
        model, source="pytorch", convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS18,
        inputs=[ct.TensorType(name="image", shape=(1, 3, 256, 256), dtype=np.float32),
                ct.TensorType(name="conditioning", shape=(1, 1), dtype=np.float32)],
        outputs=[ct.TensorType(name="denoised", dtype=np.float32)],
        compute_precision=ct.precision.FLOAT32,
        skip_model_load=not args.verify,
    )
    converted.author = "RawForge / rymuelle"
    converted.license = "MIT"
    converted.short_description = "RawForge TreeNetDenoiseSuperLight; linear Rec.2020 RGB, ISO / 6400"
    converted.input_description["image"] = "NCHW linear Rec.2020 RGB in [0,1]; 256×256"
    converted.input_description["conditioning"] = "min(ISO, 65535) / 6400"
    converted.user_defined_metadata["upstream_sha256"] = SHA256
    output = ROOT / "RawDenoise/Models/RawForgeSuperLight.mlpackage"
    converted.save(str(output))
    if args.verify:
        rng = np.random.default_rng(42)
        errors = []
        for iso in [100, 1600, 6400, 25600]:
            image = rng.uniform(0, 0.25, (1, 3, 256, 256)).astype(np.float32)
            cond = np.array([[iso / 6400]], dtype=np.float32)
            with torch.no_grad():
                expected = model(torch.from_numpy(image), torch.from_numpy(cond)).numpy()
            actual = converted.predict({"image": image, "conditioning": cond})["denoised"]
            error = float(np.max(np.abs(actual - expected)))
            errors.append({"iso": iso, "max_absolute_error": error})
            if not np.isfinite(actual).all() or error > 0.002:
                raise RuntimeError(f"Core ML parity failed at ISO {iso}: {error}")
        (ROOT / "model-parity.json").write_text(json.dumps(errors, indent=2) + "\n")
    print(f"Saved {output}")


if __name__ == "__main__":
    main()
