"""What the app does, step by step. The API file only calls these functions.

    add_material   file -> slides -> vectors in the database -> topics and key points
    answer_topic   transcript -> search in the lecture -> check -> saved attempt
    subject_view   the numbers for the Subjects screen and the topic map
"""

from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from . import check, embed, extract, rubric
from .db import Attempt, Chunk, KeyPoint, Material, Subject, Topic

# The topic map colours. Below WEAK is red, from STRONG up is green.
WEAK, STRONG = 0.5, 0.8
LAST_ATTEMPTS = 3


class NothingToLearn(ValueError):
    """The file was read, but there is no text or no topic in it."""


# ---------- upload ----------

def add_material(db: Session, subject: Subject, filename: str, path: str) -> Material:
    slides = extract.read_lecture(path)
    if not slides:
        raise NothingToLearn("No text found in this file. Scanned pages are not supported yet.")

    found = rubric.build_from_slides(slides)
    if not found["topics"]:
        raise NothingToLearn("Could not find any topic in this file.")

    material = Material(subject=subject, filename=filename, slides=len(slides))
    vectors = embed.embed([slide["text"][:2000] for slide in slides])
    material.chunks = [
        Chunk(slide=slide["slide"], text=slide["text"], embedding=vector)
        for slide, vector in zip(slides, vectors)
    ]
    material.topics = [
        Topic(
            subject=subject,
            title=topic["title"][:200],
            question=topic["question"],
            key_points=[
                KeyPoint(point=p["point"], label=p["label"][:80], slide=p["slide"])
                for p in topic["key_points"]
            ],
        )
        for topic in found["topics"]
    ]
    db.add(material)
    db.commit()
    return material


# ---------- search (RAG) ----------

def search_chunks(db: Session, material_id: int, query: str, limit: int = 3) -> list[Chunk]:
    """The slides of one material whose meaning is closest to the query."""
    vector = embed.embed_one(query)
    return list(
        db.scalars(
            select(Chunk)
            .where(Chunk.material_id == material_id)
            .order_by(Chunk.embedding.cosine_distance(vector))
            .limit(limit)
        )
    )


def _where_to_read(db: Session, topic: Topic, point: dict) -> dict:
    """The slide to read again for a missed point.

    The slide number from the rubric is used if that slide really exists.
    If the model gave no number or a wrong one, search finds the slide.
    """
    chunk = None
    if point["slide"]:
        chunk = db.scalar(
            select(Chunk).where(Chunk.material_id == topic.material_id, Chunk.slide == point["slide"])
        )
    if chunk is None:
        chunk = next(iter(search_chunks(db, topic.material_id, point["point"], limit=1)), None)
    if chunk is None:
        return {"slide": None, "snippet": "", "file": topic.material.filename}
    return {"slide": chunk.slide, "snippet": _snippet(chunk.text, point["point"]), "file": topic.material.filename}


def _snippet(text: str, about: str, limit: int = 240) -> str:
    """The part of the slide to show: it starts at the line closest to the missed point."""
    lines = [" ".join(line.split()) for line in text.splitlines() if line.strip()]
    wanted = set(about.lower().split())
    overlap = [len(wanted & set(line.lower().split())) for line in lines]
    start = overlap.index(max(overlap)) if lines and max(overlap) > 1 else 0
    snippet = " ".join(lines[start:])
    return snippet if len(snippet) <= limit else snippet[:limit].rsplit(" ", 1)[0] + "…"


# ---------- answer ----------

def answer_topic(db: Session, topic: Topic, transcript: str) -> dict:
    key_points = [{"point": k.point, "label": k.label, "slide": k.slide} for k in topic.key_points]

    excerpts = search_chunks(db, topic.material_id, topic.question)
    context = "\n\n".join(f"[slide {c.slide}]\n{c.text[:1500]}" for c in excerpts)

    result = check.check_answer(topic.question, key_points, transcript, context)
    for row in result["missed"]:
        row.update(_where_to_read(db, topic, row))

    attempt = Attempt(
        topic=topic, transcript=transcript, mastery=result["mastery"], result=result
    )
    db.add(attempt)
    db.commit()

    return {
        "attempt_id": attempt.id,
        "transcript": transcript,
        **result,
        "topic": topic_view(topic),
    }


# ---------- topic map ----------

def topic_mastery(topic: Topic) -> float | None:
    """Average of the last attempts, so one lucky answer does not turn a topic green."""
    recent = topic.attempts[-LAST_ATTEMPTS:]
    if not recent:
        return None
    return sum(a.mastery for a in recent) / len(recent)


def status_of(mastery: float | None) -> str:
    if mastery is None:
        return "new"
    if mastery < WEAK:
        return "weak"
    return "strong" if mastery >= STRONG else "ok"


def topic_view(topic: Topic) -> dict:
    mastery = topic_mastery(topic)
    last = topic.attempts[-1].result if topic.attempts else None
    return {
        "id": topic.id,
        "subject_id": topic.subject_id,
        "title": topic.title,
        "question": topic.question,
        "key_points": len(topic.key_points),
        "attempts": len(topic.attempts),
        "percent": None if mastery is None else round(mastery * 100),
        "status": status_of(mastery),
        "last_score": last["score"] if last else None,
        # The answers the percent is the average of, oldest first, like ["2/3", "0/3", "1/3"].
        "recent_scores": [a.result["score"] for a in topic.attempts[-LAST_ATTEMPTS:]],
        "last_missed": [row["label"] or row["point"] for row in last["missed"]] if last else [],
    }


def subject_view(subject: Subject, with_topics: bool = False) -> dict:
    topics = [topic_view(t) for t in subject.topics]
    # A topic nobody tried counts as 0: you cannot be ready for what you never explained.
    percent = round(sum(t["percent"] or 0 for t in topics) / len(topics)) if topics else 0
    view = {
        "id": subject.id,
        "name": subject.name,
        "exam_date": subject.exam_date.isoformat() if subject.exam_date else None,
        "days_left": (subject.exam_date - date.today()).days if subject.exam_date else None,
        "topics": len(topics),
        "weak": sum(t["status"] == "weak" for t in topics),
        "new": sum(t["status"] == "new" for t in topics),
        "percent": percent,
        "status": status_of(percent / 100) if any(t["attempts"] for t in topics) else "new",
    }
    if with_topics:
        view["topic_list"] = topics
        view["materials"] = [
            {"id": m.id, "filename": m.filename, "slides": m.slides, "topics": len(m.topics)}
            for m in subject.materials
        ]
    return view


def next_topic(subject: Subject, skip: int | None = None) -> Topic | None:
    """What to practice now: the weakest topic first, then the ones never tried.

    skip is the topic the student just answered, so "next" really moves on.
    """
    def order(topic: Topic) -> tuple:
        mastery = topic_mastery(topic)
        return (mastery is None, mastery or 0.0, len(topic.attempts), topic.id)

    topics = [t for t in subject.topics if t.id != skip] or list(subject.topics)
    weakest_first = sorted(topics, key=order)
    not_ready = [t for t in weakest_first if status_of(topic_mastery(t)) != "strong"]
    return (not_ready or weakest_first or [None])[0]
