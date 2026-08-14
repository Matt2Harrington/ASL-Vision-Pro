"""Loads the shared feature contract from config/feature_spec.json.

This is the ONLY place the Python side defines these numbers — it reads them from the
same JSON the Swift FeatureEncoder is pinned to, so the two cannot drift. Never hardcode
sequence length / feature counts elsewhere; import them from here.
"""
import json
import os

_SPEC_PATH = os.path.join(os.path.dirname(__file__), "..", "config", "feature_spec.json")

with open(_SPEC_PATH) as _f:
    SPEC = json.load(_f)

SEQ_LEN = SPEC["sequence_length"]
FEATURES_PER_FRAME = SPEC["features_per_frame"]
INPUT_SHAPE = tuple(SPEC["input_shape"])
POINTS = SPEC["points"]
COORDS_PER_POINT = SPEC["coords_per_point"]
MIN_SCALE = SPEC["normalization"]["min_scale"]
INPUT_NAME = SPEC["io"]["input_feature_name"]
OUTPUT_NAME = SPEC["io"]["output_feature_name"]

# Level-3 continuous (CTC) path.
CONTINUOUS = SPEC["continuous"]
CTX_FRAMES = CONTINUOUS["context_frames"]
CTC_OUTPUT_NAME = CONTINUOUS["output_feature_name"]
BLANK_INDEX = CONTINUOUS["blank_index"]

# Sanity check: the declared feature count must equal the layout.
_expected = (POINTS["left_hand"] + POINTS["right_hand"] + POINTS["body"] + POINTS["face"]) * COORDS_PER_POINT
assert _expected == FEATURES_PER_FRAME, (
    f"feature_spec.json inconsistent: layout implies {_expected} features/frame "
    f"but features_per_frame={FEATURES_PER_FRAME}"
)
