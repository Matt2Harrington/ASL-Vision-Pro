"""Export a trained checkpoint to a Core ML .mlpackage the app can load.

Produces input `landmarks` [1, SEQ_LEN, FEATURES_PER_FRAME] and output `probabilities`,
matching config/feature_spec.json and the Swift CoreMLSignRecognizer. Labels are attached
as metadata (comma-separated) AND written next to the model as labels.json.

Usage:
  python export_coreml.py --ckpt ckpt.pt --labels labels.json --out SignModel.mlpackage
"""
import argparse
import json

import torch

from feature_spec import SEQ_LEN, FEATURES_PER_FRAME, INPUT_NAME, OUTPUT_NAME
from model import SignClassifier, SignClassifierWithSoftmax


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ckpt", default="ckpt.pt")
    ap.add_argument("--labels", default="labels.json")
    ap.add_argument("--out", default="SignModel.mlpackage")
    ap.add_argument("--quantize", action="store_true", help="apply linear 8-bit weight quantization")
    args = ap.parse_args()

    import coremltools as ct  # imported here so train.py doesn't require coremltools

    labels = json.load(open(args.labels))
    model = SignClassifier(num_classes=len(labels))
    model.load_state_dict(torch.load(args.ckpt, map_location="cpu"))
    wrapped = SignClassifierWithSoftmax(model).eval()

    example = torch.rand(1, SEQ_LEN, FEATURES_PER_FRAME)

    # Prefer torch.export (the supported path in coremltools 8+). torch.jit.trace is legacy
    # and its trace verification fails on torch versions newer than coremltools has been
    # tested against, so it's only the fallback for older torch.
    try:
        exported = torch.export.export(wrapped, (example,))
        # Exported programs start in the TRAINING dialect, which coremltools rejects;
        # decomposing lowers it to ATEN, which is what the converter supports.
        source = exported.run_decompositions({})
        print("converting via torch.export")
    except Exception as e:
        print(f"torch.export unavailable ({type(e).__name__}), falling back to jit.trace")
        source = torch.jit.trace(wrapped, example, check_trace=False)

    mlmodel = ct.convert(
        source,
        inputs=[ct.TensorType(name=INPUT_NAME, shape=(1, SEQ_LEN, FEATURES_PER_FRAME))],
        outputs=[ct.TensorType(name=OUTPUT_NAME)],
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.ALL,
    )

    if args.quantize:
        from coremltools.optimize.coreml import (
            linear_quantize_weights, OpLinearQuantizerConfig, OptimizationConfig,
        )
        cfg = OptimizationConfig(global_config=OpLinearQuantizerConfig(mode="linear", dtype="int8"))
        mlmodel = linear_quantize_weights(mlmodel, config=cfg)

    mlmodel.user_defined_metadata["labels"] = ",".join(labels)
    mlmodel.user_defined_metadata["feature_spec_version"] = "1"
    mlmodel.save(args.out)

    with open("labels.json", "w") as f:
        json.dump(labels, f)
    print(f"saved {args.out}  (classes={len(labels)}, quantized={args.quantize})")
    print("Add SignModel.mlpackage to the app target and use CoreMLSignRecognizer(model:labels:).")


if __name__ == "__main__":
    main()
