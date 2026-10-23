"""Text -> vector. Two texts with a similar meaning get vectors that are close.

This is what makes the search work when the words differ: "threads share
memory" and "the same address space is used" end up near each other.

The model runs on this computer, so search costs nothing and needs no key.
"""

from functools import lru_cache

import numpy as np
from fastembed import TextEmbedding

from . import config


@lru_cache(maxsize=1)
def _model() -> TextEmbedding:
    # Loaded once. The very first run downloads the model (about 220 MB);
    # after that it is read from the disk and needs no internet.
    folder = str(config.MODEL_DIR / "fastembed")
    try:
        return TextEmbedding(config.EMBED_MODEL, cache_dir=folder, local_files_only=True)
    except Exception:
        return TextEmbedding(config.EMBED_MODEL, cache_dir=folder)


def warm_up() -> None:
    _model()


def embed(texts: list[str]) -> list[list[float]]:
    if not texts:
        return []
    return [vector.tolist() for vector in _model().embed(texts)]


def embed_one(text: str) -> list[float]:
    return embed([text])[0]


def similarity(a: list[float], b: list[float]) -> float:
    """Cosine similarity: 1.0 means the same meaning, near 0 means unrelated."""
    x, y = np.asarray(a), np.asarray(b)
    return float(x @ y / (np.linalg.norm(x) * np.linalg.norm(y) + 1e-9))
