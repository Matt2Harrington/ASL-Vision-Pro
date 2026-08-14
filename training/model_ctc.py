"""Level-3 continuous recognizer (CTC head) — sketch.

Maps a frame sequence [B, T, FEATURES_PER_FRAME] to per-timestep logits [B, T, V] over a
vocabulary of glosses plus a blank symbol at index BLANK_INDEX. Trained with CTC loss
(torch.nn.CTCLoss), which aligns unsegmented input to a shorter target token sequence — so
no per-frame labels are needed, only the target gloss sequence per clip.

This pairs with the Swift `ContinuousSignRecognizer` + `CTCDecoder`. Export to Core ML with
output feature name `logits` (see config/feature_spec.json → continuous). Unlike the
classifier, do NOT apply softmax before export — the Swift greedy decoder takes argmax over
raw logits per timestep.

Vocabulary convention: index 0 is BLANK. Real glosses occupy 1..V-1.
"""
import torch
import torch.nn as nn

from feature_spec import FEATURES_PER_FRAME, CTX_FRAMES


class SignCTC(nn.Module):
    def __init__(self, vocab_size: int, d_model: int = 128, nhead: int = 4,
                 num_layers: int = 4, dropout: float = 0.1):
        super().__init__()
        self.input_proj = nn.Linear(FEATURES_PER_FRAME, d_model)
        self.pos = nn.Parameter(torch.zeros(1, CTX_FRAMES, d_model))
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model, nhead=nhead, dim_feedforward=d_model * 4,
            dropout=dropout, batch_first=True, activation="gelu",
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)
        # vocab_size INCLUDES the blank symbol.
        self.head = nn.Linear(d_model, vocab_size)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: [B, T, FEATURES_PER_FRAME]  ->  logits [B, T, vocab_size]
        h = self.input_proj(x) + self.pos[:, : x.shape[1]]
        h = self.encoder(h)
        return self.head(h)


def ctc_loss_example():
    """Illustrative CTC-loss wiring (not a full trainer).

    log_probs: [T, B, V] (time-major, log-softmaxed) — note the transpose from [B, T, V].
    targets:   concatenated target gloss indices (1..V-1), with input/target lengths.
    """
    import torch.nn.functional as F

    B, T, V = 2, CTX_FRAMES, 30
    model = SignCTC(vocab_size=V)
    x = torch.rand(B, T, FEATURES_PER_FRAME)
    logits = model(x)                                  # [B, T, V]
    log_probs = F.log_softmax(logits, dim=-1).permute(1, 0, 2)   # [T, B, V]

    targets = torch.randint(1, V, (B, 5))              # 5 glosses each, none == blank(0)
    input_lengths = torch.full((B,), T, dtype=torch.long)
    target_lengths = torch.full((B,), 5, dtype=torch.long)

    loss = nn.CTCLoss(blank=0)(log_probs, targets, input_lengths, target_lengths)
    return loss
