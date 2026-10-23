"""Step 3: the student's answer -> an honest check.

The model only decides, for each key point, "did the student say this?".
Python counts the score. That is on purpose: the number must not depend
on the model's mood, and you can explain the whole rule in one sentence.
"""

import difflib
import re

from . import config, embed
from .llm import ask_json

SYSTEM = """You are checking a student's SPOKEN answer in an oral exam.

You get the question, ONE key point, and what the student said.
You may also get excerpts from the lecture; use them only to understand
what the key point means, never to give the student credit.
Decide if the student expressed this key point.

The answer is a speech transcript. Speech recognition writes some words
wrong, by their sound: "erray" is "array", "link list" is "linked list".
Read such words as the term they sound like.

Fill the fields in this order:
1. "evidence": the exact words of the student about this key point,
   or an empty string if the student said nothing about it.
2. "reason": one short sentence comparing the evidence with the key point.
3. "verdict": one of
   "said"     the evidence states the same thing as the key point,
   "hinted"   the idea only follows from the answer, or is said in part,
   "not said" nothing about it, or the opposite, or a different idea.

Rules:
- Different wording and synonyms are fine ("memory space" = "address space").
- Saying a term without explaining it is NOT covered.
- A statement that says the opposite of the key point is NOT covered.
- A statement about a different idea is NOT covered, even if it is correct.
- The evidence must name the specific property of the key point (time,
  memory, size, order...). A general word like "easier" or "better" is
  "hinted", not "said".
- Be strict but fair.

Answer with JSON only:
{"evidence": "...", "reason": "...", "verdict": "said"}"""

# Offline mode only: how close an answer sentence must be to a key point.
# Measured on sample answers: off-topic ones stay below 0.5, good ones are
# mostly above 0.7.
OFFLINE_THRESHOLD = 0.7


def check_answer(question: str, key_points: list[dict], answer: str, context: str = "") -> dict:
    if config.llm_is_configured():
        raw = _ask_model(question, key_points, answer, context)
    else:
        raw = _offline_check(key_points, answer)

    # Python builds the final report, not the model.
    covered_flags = {item["index"]: item for item in raw.get("results", [])}
    named, missed = [], []
    for i, point in enumerate(key_points, start=1):
        item = covered_flags.get(i, {})
        row = {
            "point": point["point"],
            "label": point.get("label", ""),
            "slide": point.get("slide"),
            "evidence": item.get("evidence", ""),
        }
        # No quote from the student means no credit, whatever the model decided.
        (named if item.get("covered") and row["evidence"] else missed).append(row)

    return {
        "named": named,
        "missed": missed,
        "score": f"{len(named)}/{len(key_points)}",
        "mastery": round(len(named) / len(key_points), 2) if key_points else 0.0,
    }


def _ask_model(question: str, key_points: list[dict], answer: str, context: str) -> dict:
    """One request per key point. A small model judges one idea at a time
    much better than four at once."""
    results = []
    for i, point in enumerate(key_points, start=1):
        user = f"QUESTION:\n{question}\n\nKEY POINT:\n{point['point']}\n\n"
        if context:
            user += f"LECTURE EXCERPTS:\n{context}\n\n"
        user += f"STUDENT SAID:\n{answer}"
        reply = ask_json(SYSTEM, user)
        evidence = str(reply.get("evidence", ""))
        results.append(
            {
                "index": i,
                "evidence": evidence,
                # Only a clear "said" counts, and only with a real quote behind it.
                "covered": reply.get("verdict") == "said" and is_quote(evidence, answer),
            }
        )
    return {"results": results}


def is_quote(evidence: str, answer: str) -> bool:
    """True if the evidence really is a piece of the answer.

    A model can invent a quote that sounds right. This is the guard: at least
    80% of the quoted words must be found in the answer, in the same order.
    """
    quoted, said = _words(evidence), _words(answer)
    if not quoted:
        return False
    matcher = difflib.SequenceMatcher(None, quoted, said, autojunk=False)
    found = sum(block.size for block in matcher.get_matching_blocks())
    return found / len(quoted) >= 0.8


def _words(text: str) -> list[str]:
    return re.findall(r"\w+", text.lower())


def _offline_check(key_points: list[dict], answer: str) -> dict:
    """No API key: compare meanings with vectors instead of asking a model.

    Rougher than the real check (it cannot tell "explained" from "mentioned"),
    but it follows the same rule: one decision per key point.
    """
    sentences = [s.strip() for s in re.split(r"(?<=[.!?…])\s+|\n+", answer) if s.strip()]
    # Speech often splits one idea over two sentences, so also try neighbours together.
    sentences += [f"{a} {b}" for a, b in zip(sentences, sentences[1:])] or [answer]
    sentence_vectors = embed.embed(sentences)
    point_vectors = embed.embed([point["point"] for point in key_points])

    results = []
    for i, point_vector in enumerate(point_vectors, start=1):
        scores = [embed.similarity(point_vector, v) for v in sentence_vectors]
        best = max(range(len(scores)), key=scores.__getitem__)
        covered = scores[best] >= OFFLINE_THRESHOLD
        results.append({"index": i, "covered": covered, "evidence": sentences[best] if covered else ""})
    return {"results": results}
