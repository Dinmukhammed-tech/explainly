"""One place that talks to the AI model.

Everything else in the project calls ask_json() and gets a Python dict back.
If you change the provider later, you only change this file.
"""

import json
from functools import lru_cache

from openai import OpenAI

from . import config


@lru_cache(maxsize=1)
def client() -> OpenAI:
    if not config.llm_is_configured():
        raise RuntimeError(
            "LLM_API_KEY is not set. Copy .env.example to .env and put your key there."
        )
    # base_url lets you use OpenAI, OpenRouter, Groq or a local model
    # without changing any other code.
    return OpenAI(api_key=config.LLM_API_KEY, base_url=config.LLM_BASE_URL or None)


def warm_up() -> None:
    """Make the provider load the model now. A local model (Ollama) needs
    some seconds for that, and the first student should not wait for it."""
    if config.llm_is_configured():
        ask_json("Answer with JSON only.", 'Reply {"ok": true}')


def ask_json(system_prompt: str, user_prompt: str) -> dict:
    """Send a prompt, get a JSON object back as a dict."""
    response = client().chat.completions.create(
        model=config.LLM_MODEL,
        temperature=0,  # we want the same answer every time, not creativity
        response_format={"type": "json_object"},
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
    )
    text = response.choices[0].message.content
    return json.loads(text)
