"""Step 2: the lecture -> topics, questions and KEY POINTS.

This is the most important file in the project. The key points are what
makes the check honest: the app does not ask the model "was this answer
good?", it asks "which of these points did the student say?".

The result is saved (to a JSON file in the demo, to the database in the
server), so you pay the API once per lecture.
"""

import json
import re
from collections import Counter
from pathlib import Path

from . import config, extract
from .llm import ask_json

SYSTEM = """You are a university lecturer preparing an ORAL exam.
You are given the text of one lecture, with slide numbers.

For each topic you find, write:
- an open question that cannot be answered with one word,
- the key points a full spoken answer must contain,
- for every key point, a label of 1 to 3 words that names it,
- for every key point, the slide number where it is explained.

Rules:
- Use ONLY what is in the lecture text. Never add outside knowledge.
- A key point is one short sentence, in the lecture's own terms.
- A key point states a fact the student can say out loud. It is never a
  task like "Implement a stack" or "Use generics".
- Give each topic 2 to 4 key points.
- Write everything in English.

Answer with JSON only, in this shape:
{"topics": [
  {"title": "...",
   "question": "...",
   "key_points": [{"point": "...", "label": "...", "slide": 12}]}
]}"""


# A list topic may have this many key points. More would make the check slow:
# every key point is one request to the model.
MAX_POINTS = 8

BULLETS = "•・▪◦‣●○■*-–"


def build_rubric(lecture_text: str, max_topics: int = 5) -> dict:
    user = (
        f"Find at most {max_topics} topics in this lecture.\n\n"
        f"LECTURE TEXT:\n{lecture_text}"
    )
    return ask_json(SYSTEM, user)


def build_from_slides(slides: list[dict], max_topics: int = 8) -> dict:
    """The entry point the server uses. Works with or without an API key.

    A long lecture is cut into parts that fit into one request, and each
    part gets its share of the topics.
    """
    if not config.llm_is_configured():
        return normalize(offline_rubric(slides, max_topics))

    parts = extract.split_for_prompt(slides, config.LLM_MAX_CHARS)
    per_part = max(1, max_topics // len(parts))
    topics: list[dict] = []
    for part in parts:
        topics += build_rubric(extract.as_prompt_text(part), per_part).get("topics", [])
    return expand_lists(normalize({"topics": topics[:max_topics]}), slides)


def list_items(text: str) -> list[str]:
    """The items of a slide that is a short list, like "Stack applications".

    Returns [] for any other slide. A list slide has at least 4 items and
    every item is a short name (up to 7 words), not a sentence or code.
    """
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    marked = [line.lstrip(BULLETS + " \t") for line in lines if line[0] in BULLETS]
    items = marked or lines[1:]  # no bullet signs: the first line is the title
    items = [item for item in items if re.search(r"[A-Za-z]", item)]  # drops "..." and page numbers
    is_name = lambda item: len(item.split()) <= 7 and not re.search(r"[{}()=;<>]", item)
    return items if len(items) >= 4 and all(map(is_name, items)) else []


def expand_lists(rubric: dict, slides: list[dict]) -> dict:
    """If a key point comes from a list slide, ask for EVERY item of that list.

    The model picks 2 or 3 items of a list and drops the rest, so a student
    who names all of them gets no credit for most. This is done in code,
    not by the model, so it works the same way every time.
    """
    lists = {slide["slide"]: list_items(slide["text"]) for slide in slides}
    # The same list on several slides is the lecture outline, not content.
    seen = Counter(tuple(items) for items in lists.values() if items)
    lists = {number: items for number, items in lists.items() if seen[tuple(items)] == 1}

    for topic in rubric["topics"]:
        from_lists, others, done = [], [], set()
        for point in topic["key_points"]:
            items = lists.get(point["slide"])
            if not items:
                others.append(point)
            elif point["slide"] not in done:
                done.add(point["slide"])
                from_lists += [
                    {"point": item, "label": item.strip(" .,;:"), "slide": point["slide"]} for item in items
                ]
        # A point from another slide may repeat a list item in other words.
        others = [p for p in others if not any(_same_idea(item["point"], p["point"]) for item in from_lists)]
        topic["key_points"] = (from_lists + others)[:MAX_POINTS]
    return rubric


def _same_idea(item: str, point: str) -> bool:
    """True if nearly all words of the list item are also in the other key point."""
    stem = lambda text: {word[:6] for word in re.findall(r"[a-z]+", text.lower())}
    words = stem(item)
    return len(words & stem(point)) >= 0.8 * len(words)


def offline_rubric(slides: list[dict], max_topics: int) -> dict:
    """A rough rubric made without AI: slide title -> topic, bullets -> key points.

    It only exists so the app can be tried before you have an API key.
    The questions are much better with a real model.
    """
    topics = []
    for slide in slides:
        lines = [line.strip(" \t•-–—*·") for line in slide["text"].splitlines()]
        lines = [line for line in lines if line]
        if len(lines) < 3:
            continue
        title = lines[0]
        points = [line for line in lines[1:] if len(line.split()) >= 4][:4]
        if len(points) < 2:
            continue
        topics.append(
            {
                "title": title,
                "question": f"Explain: {title}",
                "key_points": [{"point": point, "slide": slide["slide"]} for point in points],
            }
        )
    return {"topics": topics[:max_topics]}


def normalize(rubric: dict) -> dict:
    """Clean what the model returned, so the rest of the code can trust it."""
    topics = []
    for topic in rubric.get("topics", []):
        points = []
        for item in topic.get("key_points", []):
            text = str(item.get("point", "")).strip()
            if not text:
                continue
            slide = item.get("slide")
            points.append(
                {
                    "point": text,
                    "label": str(item.get("label") or " ".join(text.split()[:3])).strip(" .,;:"),
                    "slide": slide if isinstance(slide, int) and slide > 0 else None,
                }
            )
        title = str(topic.get("title", "")).strip()
        question = str(topic.get("question", "")).strip()
        if not (title and question and points):
            continue
        # A small model sometimes cuts one topic into two questions. Put them back together.
        same = next((t for t in topics if t["title"].lower() == title.lower()), None)
        if same:
            same["key_points"] = (same["key_points"] + points)[:MAX_POINTS]
        else:
            topics.append({"title": title, "question": question, "key_points": points[:MAX_POINTS]})
    return {"topics": topics}


def save(rubric: dict, path: str) -> None:
    Path(path).write_text(json.dumps(rubric, ensure_ascii=False, indent=2), encoding="utf-8")


def load(path: str) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))
