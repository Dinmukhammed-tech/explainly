"""The server. The mobile app talks only to this file.

    uvicorn app.main:app --host 0.0.0.0 --port 8000
    open http://localhost:8000/docs to try every request in the browser

This file only receives requests and returns answers.
The real work is in services.py.
"""

import os
import tempfile
import threading
from contextlib import asynccontextmanager
from datetime import date
from pathlib import Path

from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from openai import OpenAIError
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from . import config, embed, llm, services, transcribe
from .db import Subject, Topic, get_session, init_db


def warm_up() -> None:
    """Load every model before the first request needs it."""
    for name, load in [("search", embed.warm_up), ("Whisper", transcribe.warm_up), ("AI", llm.warm_up)]:
        try:
            load()
            print(f"Model ready: {name}", flush=True)
        except Exception as error:  # the server still works, the first request will just be slow
            print(f"Model not ready: {name}: {error}", flush=True)


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    if config.WARM_UP:
        # In the background, so the server answers at once while the models load.
        threading.Thread(target=warm_up, daemon=True).start()
    yield


app = FastAPI(title="Explainly", lifespan=lifespan)

# The app runs on a phone or in a browser, so requests come from another address.
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


class SubjectIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    exam_date: date | None = None


def get_subject(subject_id: int, db: Session = Depends(get_session)) -> Subject:
    subject = db.get(Subject, subject_id)
    if subject is None:
        raise HTTPException(404, "Subject not found")
    return subject


def get_topic(topic_id: int, db: Session = Depends(get_session)) -> Topic:
    topic = db.get(Topic, topic_id)
    if topic is None:
        raise HTTPException(404, "Topic not found")
    return topic


def save_upload(upload: UploadFile) -> str:
    """Put an uploaded file on disk for a moment. The caller deletes it."""
    suffix = Path(upload.filename or "").suffix.lower()
    limit = config.MAX_UPLOAD_MB * 1024 * 1024
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as out:
        size = 0
        while block := upload.file.read(1024 * 1024):
            size += len(block)
            if size > limit:
                out.close()
                os.unlink(out.name)
                raise HTTPException(413, f"File is larger than {config.MAX_UPLOAD_MB} MB")
            out.write(block)
    return out.name


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "ai": config.LLM_MODEL if config.llm_is_configured() else "offline",
        "whisper": config.WHISPER_MODE,
    }


# ---------- subjects ----------

@app.get("/subjects")
def list_subjects(db: Session = Depends(get_session)) -> list[dict]:
    subjects = db.scalars(select(Subject).order_by(Subject.id))
    return [services.subject_view(s) for s in subjects]


@app.post("/subjects", status_code=201)
def create_subject(body: SubjectIn, db: Session = Depends(get_session)) -> dict:
    subject = Subject(name=body.name.strip(), exam_date=body.exam_date)
    db.add(subject)
    db.commit()
    return services.subject_view(subject)


@app.get("/subjects/{subject_id}")
def read_subject(subject: Subject = Depends(get_subject)) -> dict:
    """One subject with its topic map."""
    return services.subject_view(subject, with_topics=True)


@app.put("/subjects/{subject_id}")
def update_subject(
    body: SubjectIn, subject: Subject = Depends(get_subject), db: Session = Depends(get_session)
) -> dict:
    subject.name, subject.exam_date = body.name.strip(), body.exam_date
    db.commit()
    return services.subject_view(subject)


@app.delete("/subjects/{subject_id}", status_code=204)
def delete_subject(subject: Subject = Depends(get_subject), db: Session = Depends(get_session)) -> None:
    db.delete(subject)
    db.commit()


@app.post("/subjects/{subject_id}/materials", status_code=201)
def upload_material(
    file: UploadFile = File(...),
    subject: Subject = Depends(get_subject),
    db: Session = Depends(get_session),
) -> dict:
    """Upload a lecture (.pdf or .pptx). The server reads it and writes the questions."""
    if Path(file.filename or "").suffix.lower() not in {".pdf", ".pptx"}:
        raise HTTPException(415, "Only .pdf and .pptx files are supported")
    path = save_upload(file)
    try:
        material = services.add_material(db, subject, file.filename, path)
    except services.NothingToLearn as error:
        raise HTTPException(422, str(error))
    except OpenAIError as error:
        raise HTTPException(502, f"The AI model did not answer: {error}")
    finally:
        os.unlink(path)
    return {
        "material": {"id": material.id, "filename": material.filename, "slides": material.slides},
        "topics_added": len(material.topics),
        "subject": services.subject_view(subject, with_topics=True),
    }


@app.get("/subjects/{subject_id}/next")
def next_topic(skip: int | None = None, subject: Subject = Depends(get_subject)) -> dict:
    """The topic to practice now: the weakest one."""
    topic = services.next_topic(subject, skip)
    if topic is None:
        raise HTTPException(404, "This subject has no topics yet. Add a material first.")
    return services.topic_view(topic)


# ---------- topics ----------

@app.get("/topics/{topic_id}")
def read_topic(topic: Topic = Depends(get_topic)) -> dict:
    """The question. The key points are not sent: the student must not see them first."""
    return services.topic_view(topic)


@app.post("/topics/{topic_id}/answer")
def answer(
    audio: UploadFile | None = File(None),
    text: str = Form(""),
    topic: Topic = Depends(get_topic),
    db: Session = Depends(get_session),
) -> dict:
    """Send a voice recording (or typed text) and get the check back."""
    transcript = text.strip()
    if audio is not None:
        path = save_upload(audio)
        try:
            transcript = transcribe.transcribe(path, hint=f"{topic.title}. {topic.question}")
        except OpenAIError as error:
            raise HTTPException(502, f"Speech recognition failed: {error}")
        finally:
            os.unlink(path)
    if not transcript:
        raise HTTPException(422, "No speech was heard. Try again, closer to the microphone.")
    try:
        return services.answer_topic(db, topic, transcript)
    except OpenAIError as error:
        raise HTTPException(502, f"The AI model did not answer: {error}")


@app.get("/topics/{topic_id}/attempts")
def attempts(topic: Topic = Depends(get_topic)) -> list[dict]:
    return [
        {
            "id": a.id,
            "created_at": a.created_at.isoformat(),
            "transcript": a.transcript,
            **a.result,
        }
        for a in reversed(topic.attempts)
    ]


# ---------- the web version of the app ----------

# The same Flutter app, built for the browser (mobile/build/web). The server
# gives it out itself, so one address opens it: http://localhost:8000
# This must stay last: every address above is tried first.
WEB_APP = config.ROOT / "mobile" / "build" / "web"


class WebApp(StaticFiles):
    """Tells the browser to check for a newer version every time.

    Without this the browser keeps the old app after a rebuild and the
    changes do not show until its cache is cleared by hand.
    """

    async def get_response(self, path, scope):
        response = await super().get_response(path, scope)
        response.headers["Cache-Control"] = "no-cache"
        return response


if WEB_APP.exists():
    app.mount("/", WebApp(directory=WEB_APP, html=True), name="web")
