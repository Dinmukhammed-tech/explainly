"""All settings in one place. Values come from the .env file.

Nothing else in the project reads os.environ for settings, so when you
wonder "where is this configured?", the answer is always this file.
"""

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_env(path: Path = ROOT / ".env") -> None:
    """Tiny .env reader, so you do not need an extra library."""
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            name, value = line.split("=", 1)
            os.environ.setdefault(name.strip(), value.strip())


load_env()

DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql+psycopg://explainly:explainly@localhost:5433/explainly"
)

LLM_API_KEY = os.getenv("LLM_API_KEY", "")
LLM_BASE_URL = os.getenv("LLM_BASE_URL", "")
LLM_MODEL = os.getenv("LLM_MODEL", "gpt-4o-mini")
# How many characters of a lecture go into one request. A local model
# (Ollama) reads less at once than a cloud one, so use about 10000 there.
LLM_MAX_CHARS = int(os.getenv("LLM_MAX_CHARS", "30000"))

# "local" runs Whisper on this computer (free, no key).
# "api" sends the audio to the provider from LLM_BASE_URL (faster, needs a key).
WHISPER_MODE = os.getenv("WHISPER_MODE", "local")
WHISPER_MODEL = os.getenv("WHISPER_MODEL", "small")
WHISPER_API_MODEL = os.getenv("WHISPER_API_MODEL", "whisper-1")

# Turns text into vectors for search. Small enough to run on a laptop.
EMBED_MODEL = os.getenv("EMBED_MODEL", "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2")
EMBED_DIM = 384

# Downloaded models are kept here. Not in /tmp: that folder is emptied when
# the computer restarts, and the models would be downloaded again.
MODEL_DIR = Path(os.getenv("MODEL_DIR", Path.home() / ".cache" / "explainly"))

# Load the models when the server starts, so the first answer is not slow.
# The tests switch this off: they do not need Whisper.
WARM_UP = os.getenv("WARM_UP", "1") == "1"

MAX_UPLOAD_MB = int(os.getenv("MAX_UPLOAD_MB", "40"))


def llm_is_configured() -> bool:
    """False while .env still has the placeholder key. Then the app works offline."""
    return bool(LLM_API_KEY) and not LLM_API_KEY.startswith("put-")
