"""Voice -> text with Whisper.

There are two ways to run Whisper, and the rest of the app does not care
which one is used (this is the Strategy pattern):

    LocalWhisper  runs on this computer. Free, private, slower.
    ApiWhisper    sends the audio to the provider. Fast, needs a key.

Pick one with WHISPER_MODE in .env.
"""

from functools import lru_cache
from typing import Protocol

from . import config

# The app is English only. Telling Whisper the language makes it more exact
# than letting it guess.
LANGUAGE = "en"


class Transcriber(Protocol):
    def transcribe(self, audio_path: str, hint: str) -> str:
        """Return what was said. hint is text with the terms to expect."""


class LocalWhisper:
    def __init__(self, model_name: str) -> None:
        from faster_whisper import WhisperModel

        # int8 makes the model small and fast enough for a normal CPU.
        options = dict(device="cpu", compute_type="int8", download_root=str(config.MODEL_DIR / "whisper"))
        try:
            # Read from the disk if it is already there: no internet needed.
            self.model = WhisperModel(model_name, local_files_only=True, **options)
        except Exception:
            self.model = WhisperModel(model_name, **options)

    def transcribe(self, audio_path: str, hint: str) -> str:
        segments, _ = self.model.transcribe(
            audio_path,
            language=LANGUAGE,
            initial_prompt=hint or None,
            vad_filter=True,  # skip silence, so pauses do not turn into made-up words
        )
        return " ".join(segment.text.strip() for segment in segments).strip()


class ApiWhisper:
    def transcribe(self, audio_path: str, hint: str) -> str:
        from .llm import client

        with open(audio_path, "rb") as audio:
            response = client().audio.transcriptions.create(
                model=config.WHISPER_API_MODEL,
                file=audio,
                language=LANGUAGE,
                prompt=hint,
            )
        return response.text.strip()


@lru_cache(maxsize=1)
def get_transcriber() -> Transcriber:
    if config.WHISPER_MODE == "api":
        return ApiWhisper()
    return LocalWhisper(config.WHISPER_MODEL)


def warm_up() -> None:
    get_transcriber()


def transcribe(audio_path: str, hint: str = "") -> str:
    """hint tells Whisper which words to expect, so it writes "array" and
    not "erray". Give it the question, never the key points: the hint must
    not put the right answer into the student's mouth."""
    return get_transcriber().transcribe(audio_path, hint)
