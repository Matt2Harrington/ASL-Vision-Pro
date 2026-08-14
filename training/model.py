"""Compact temporal Transformer classifier for isolated signs / fingerspelling.

Sized to fit the Vision Pro / iPhone Neural Engine after quantization. Input is a window
of normalized landmarks [B, SEQ_LEN, FEATURES_PER_FRAME]; output is class logits.
"""
import torch
import torch.nn as nn

from feature_spec import SEQ_LEN, FEATURES_PER_FRAME


class SignClassifier(nn.Module):
    def __init__(self, num_classes: int, d_model: int = 128, nhead: int = 4,
                 num_layers: int = 4, dropout: float = 0.1):
        super().__init__()
        self.input_proj = nn.Linear(FEATURES_PER_FRAME, d_model)
        self.pos = nn.Parameter(torch.zeros(1, SEQ_LEN, d_model))
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model, nhead=nhead, dim_feedforward=d_model * 4,
            dropout=dropout, batch_first=True, activation="gelu",
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)
        self.head = nn.Sequential(
            nn.LayerNorm(d_model),
            nn.Linear(d_model, num_classes),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: [B, SEQ_LEN, FEATURES_PER_FRAME]
        h = self.input_proj(x) + self.pos
        h = self.encoder(h)
        h = h.mean(dim=1)            # temporal mean-pool
        return self.head(h)          # logits [B, num_classes]


class SignClassifierWithSoftmax(nn.Module):
    """Wraps the classifier to emit probabilities — used only for Core ML export so the
    on-device output feature matches the `probabilities` name the Swift recognizer reads."""
    def __init__(self, model: SignClassifier):
        super().__init__()
        self.model = model

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return torch.softmax(self.model(x), dim=-1)
